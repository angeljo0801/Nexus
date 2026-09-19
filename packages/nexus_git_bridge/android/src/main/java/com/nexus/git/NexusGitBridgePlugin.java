package com.nexus.git;

import androidx.annotation.NonNull;

import org.eclipse.jgit.api.Git;
import org.eclipse.jgit.api.Status;
import org.eclipse.jgit.diff.DiffEntry;
import org.eclipse.jgit.diff.DiffFormatter;
import org.eclipse.jgit.lib.StoredConfig;
import org.eclipse.jgit.lib.Constants;
import org.eclipse.jgit.lib.ObjectId;
import org.eclipse.jgit.lib.Ref;
import org.eclipse.jgit.lib.Repository;
import org.eclipse.jgit.revwalk.RevCommit;
import org.eclipse.jgit.revwalk.RevTree;
import org.eclipse.jgit.revwalk.RevWalk;
import org.eclipse.jgit.storage.file.FileRepositoryBuilder;
import org.eclipse.jgit.transport.RefSpec;
import org.eclipse.jgit.transport.UsernamePasswordCredentialsProvider;
import org.eclipse.jgit.treewalk.FileTreeIterator;
import org.eclipse.jgit.treewalk.filter.PathFilterGroup;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import android.os.Handler;
import android.os.Looper;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public final class NexusGitBridgePlugin
        implements FlutterPlugin, MethodChannel.MethodCallHandler {

    private MethodChannel channel;
    private final ExecutorService gitExecutor =
            Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "com.nexus/git");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(
            @NonNull MethodCall call,
            @NonNull MethodChannel.Result result
    ) {
        gitExecutor.execute(() -> {
            try {
                switch (call.method) {
                    case "init":
                        init(call);
                        postSuccess(result, null);
                        break;
                    case "status":
                        postSuccess(result, status(call));
                        break;
                    case "diff":
                        postSuccess(result, diff(call));
                        break;
                    case "commitAll":
                        postSuccess(result, commitAll(call));
                        break;
                    case "setRemote":
                        setRemote(call);
                        postSuccess(result, null);
                        break;
                    case "push":
                        push(call);
                        postSuccess(result, null);
                        break;
                    case "clone":
                        cloneRepository(call);
                        postSuccess(result, null);
                        break;
                    default:
                        mainHandler.post(result::notImplemented);
                }
            } catch (Exception error) {
                postError(result, error);
            }
        });
    }

    private void postSuccess(
            MethodChannel.Result result,
            Object value
    ) {
        mainHandler.post(() -> result.success(value));
    }

    private void postError(
            MethodChannel.Result result,
            Exception error
    ) {
        final String message = error.getMessage() == null
                ? error.getClass().getSimpleName()
                : error.getMessage();
        mainHandler.post(
                () -> result.error(
                        "GIT_ERROR",
                        message,
                        error.getClass().getSimpleName()
                )
        );
    }

    private String requiredString(MethodCall call, String key) {
        final String value = call.argument(key);
        if (value == null || value.trim().isEmpty()) {
            throw new IllegalArgumentException("Missing argument: " + key);
        }
        return value.trim();
    }

    private Git openGit(String repoPath) throws Exception {
        final File directory = new File(repoPath);
        final FileRepositoryBuilder builder = new FileRepositoryBuilder()
                .setWorkTree(directory)
                .readEnvironment()
                .findGitDir(directory);
        final Repository repository = builder.build();
        if (repository.getDirectory() == null || !repository.getDirectory().exists()) {
            repository.close();
            throw new IllegalStateException("Workspace is not a Git repository.");
        }
        return new Git(repository);
    }

    private void init(MethodCall call) throws Exception {
        final String repoPath = requiredString(call, "repoPath");
        final String branch = call.argument("branch") == null
                ? "main"
                : requiredString(call, "branch");
        final File workTree = new File(repoPath);
        if (!workTree.exists() && !workTree.mkdirs()) {
            throw new IllegalStateException("Could not create project workspace.");
        }

        final File dotGit = new File(workTree, ".git");
        if (!dotGit.exists()) {
            try (Git git = Git.init()
                    .setDirectory(workTree)
                    .setInitialBranch(branch)
                    .call()) {
                final StoredConfig config = git.getRepository().getConfig();
                config.setBoolean("core", null, "filemode", false);
                config.save();
            }
        }
    }

    private Map<String, Object> status(MethodCall call) throws Exception {
        final String repoPath = requiredString(call, "repoPath");
        try (Git git = openGit(repoPath)) {
            final Status status = git.status().call();
            final Map<String, Object> result = new HashMap<>();
            result.put("branch", git.getRepository().getBranch());
            result.put("clean", status.isClean());
            result.put("added", new ArrayList<>(status.getAdded()));
            result.put("changed", new ArrayList<>(status.getChanged()));
            result.put("modified", new ArrayList<>(status.getModified()));
            result.put("missing", new ArrayList<>(status.getMissing()));
            result.put("removed", new ArrayList<>(status.getRemoved()));
            result.put("untracked", new ArrayList<>(status.getUntracked()));
            return result;
        }
    }

    private String diff(MethodCall call) throws Exception {
        final String repoPath = requiredString(call, "repoPath");
        try (Git git = openGit(repoPath);
             ByteArrayOutputStream output = new ByteArrayOutputStream();
             DiffFormatter formatter = new DiffFormatter(output)) {

            final Repository repository = git.getRepository();
            formatter.setRepository(repository);
            formatter.setDetectRenames(true);

            final ObjectId head = repository.resolve(Constants.HEAD + "^{tree}");
            final FileTreeIterator workingTree = new FileTreeIterator(repository);

            if (head == null) {
                final List<DiffEntry> entries = git.diff()
                        .setOldTree(new org.eclipse.jgit.treewalk.EmptyTreeIterator())
                        .setNewTree(workingTree)
                        .call();
                for (final DiffEntry entry : entries) {
                    formatter.format(entry);
                }
            } else {
                try (RevWalk walk = new RevWalk(repository)) {
                    final RevCommit commit = walk.parseCommit(repository.resolve(Constants.HEAD));
                    final RevTree tree = commit.getTree();
                    final org.eclipse.jgit.treewalk.CanonicalTreeParser oldTree =
                            new org.eclipse.jgit.treewalk.CanonicalTreeParser();
                    try (org.eclipse.jgit.lib.ObjectReader reader = repository.newObjectReader()) {
                        oldTree.reset(reader, tree.getId());
                    }
                    final List<DiffEntry> entries = git.diff()
                            .setOldTree(oldTree)
                            .setNewTree(workingTree)
                            .call();
                    for (final DiffEntry entry : entries) {
                        formatter.format(entry);
                    }
                }
            }

            formatter.flush();
            return output.toString(StandardCharsets.UTF_8.name());
        }
    }

    private Map<String, Object> commitAll(MethodCall call) throws Exception {
        final String repoPath = requiredString(call, "repoPath");
        final String message = requiredString(call, "message");
        final String authorName = call.argument("authorName") == null
                ? "Nexus"
                : requiredString(call, "authorName");
        final String authorEmail = call.argument("authorEmail") == null
                ? "nexus@local"
                : requiredString(call, "authorEmail");

        try (Git git = openGit(repoPath)) {
            final Status before = git.status().call();
            final Map<String, Object> result = new HashMap<>();
            if (before.isClean()) {
                final ObjectId head = git.getRepository().resolve(Constants.HEAD);
                result.put("sha", head == null ? "" : head.name());
                result.put("message", message);
                result.put("created", false);
                return result;
            }

            git.add().addFilepattern(".").call();
            git.add().setUpdate(true).addFilepattern(".").call();

            final RevCommit commit = git.commit()
                    .setMessage(message)
                    .setAuthor(authorName, authorEmail)
                    .setCommitter(authorName, authorEmail)
                    .call();

            result.put("sha", commit.getName());
            result.put("message", commit.getShortMessage());
            result.put("created", true);
            return result;
        }
    }

    private void setRemote(MethodCall call) throws Exception {
        final String repoPath = requiredString(call, "repoPath");
        final String remoteUrl = requiredString(call, "remoteUrl");
        try (Git git = openGit(repoPath)) {
            final StoredConfig config = git.getRepository().getConfig();
            config.setString("remote", "origin", "url", remoteUrl);
            config.setString("remote", "origin", "fetch", "+refs/heads/*:refs/remotes/origin/*");
            config.save();
        }
    }

    private void push(MethodCall call) throws Exception {
        final String repoPath = requiredString(call, "repoPath");
        final String token = requiredString(call, "token");
        final String remote = call.argument("remote") == null
                ? "origin"
                : requiredString(call, "remote");
        final String branch = call.argument("branch") == null
                ? "main"
                : requiredString(call, "branch");

        try (Git git = openGit(repoPath)) {
            git.push()
                    .setRemote(remote)
                    .setRefSpecs(new RefSpec(
                            "refs/heads/" + branch + ":refs/heads/" + branch
                    ))
                    .setCredentialsProvider(
                            new UsernamePasswordCredentialsProvider(
                                    "x-access-token",
                                    token
                            )
                    )
                    .call();
        }
    }

    private void cloneRepository(MethodCall call) throws Exception {
        final String remoteUrl = requiredString(call, "remoteUrl");
        final String destinationPath = requiredString(call, "destinationPath");
        final String branch = call.argument("branch") == null
                ? "main"
                : requiredString(call, "branch");
        final String token = call.argument("token");

        final File destination = new File(destinationPath);
        if (destination.exists()) {
            final String[] children = destination.list();
            if (children != null && children.length > 0) {
                throw new IllegalStateException("Destination workspace is not empty.");
            }
        } else if (!destination.mkdirs()) {
            throw new IllegalStateException("Could not create clone destination.");
        }

        final org.eclipse.jgit.api.CloneCommand command = Git.cloneRepository()
                .setURI(remoteUrl)
                .setDirectory(destination)
                .setBranch("refs/heads/" + branch)
                .setCloneAllBranches(false);

        if (token != null && !token.trim().isEmpty()) {
            command.setCredentialsProvider(
                    new UsernamePasswordCredentialsProvider(
                            "x-access-token",
                            token.trim()
                    )
            );
        }

        try (Git ignored = command.call()) {
            // Repository is ready.
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
        }
        channel = null;
        gitExecutor.shutdownNow();
    }
}
