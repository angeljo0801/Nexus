import json
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent))
from prepare_lora_dataset import read_rows, main


class DatasetChecks(unittest.TestCase):
    def test_deduplication(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"sample.jsonl"
            row={"messages":[{"role":"user","content":"Hola"},{"role":"assistant","content":"¡Hola!"}]}
            path.write_text((json.dumps(row)+"\n")*2,encoding="utf-8")
            self.assertEqual(len(list(read_rows(path))),1)

    def test_invalid_role(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"bad.jsonl"
            path.write_text(json.dumps({"messages":[{"role":"assistant","content":"x"},{"role":"user","content":"y"}]}),encoding="utf-8")
            with self.assertRaises(ValueError):
                list(read_rows(path))


if __name__ == "__main__":
    unittest.main()
