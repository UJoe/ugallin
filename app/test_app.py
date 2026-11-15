"""Unit test, run by the pipeline before anything is built or deployed:
    python3 -m unittest -v
"""
import unittest

from app import greeting


class TestGreeting(unittest.TestCase):
    def test_greeting(self):
        self.assertTrue(greeting().startswith("Hello from ugallin!"))


if __name__ == "__main__":
    unittest.main()
