
from cern.pymad import tfs
import unittest


class TestTFS(unittest.TestCase):
    def test_wrongpath(self):
        self.assertRaises(ValueError, tfs, 'wrong_file_path')


if __name__ == '__main__':
    unittest.main()
