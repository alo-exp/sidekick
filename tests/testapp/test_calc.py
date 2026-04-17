import unittest

from calc import add, sub


class TestCalc(unittest.TestCase):
    def test_add_positive(self):
        self.assertEqual(add(2, 3), 5)

    def test_add_negative_and_positive(self):
        self.assertEqual(add(-1, 1), 0)

    def test_sub(self):
        self.assertEqual(sub(5, 3), 2)


if __name__ == "__main__":
    unittest.main()
