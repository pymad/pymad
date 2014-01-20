# encoding: utf-8
"""
Unit tests for the resource components
"""
# from __future__ import unicode_literals

# NOTE: The python2 setuptools.setup call expects pure binary (bytes) input
# parameters. It is therefore impractical to use module-level unicode
# support via the prededing __future__ import. The tests work on python2
# anyway since implicit coercion between unicode and bytes is possible. On
# python3 this is not possible, but not needed.

# tested classes
from cern.resource.package import PackageResource
from cern.resource.file import FileResource
from cern.resource.couch import CouchResource

# test utilities
import unittest
import tempfile
import shutil
import yaml
import os.path
import gc
import sys
import setuptools
import contextlib
from io import open

def create_test_file(base, path, content=None):
    """
    Create a file with defined content under base/path.
    """
    try:
        os.makedirs(os.path.join(base, *path[:-1]))
    except OSError:
        # directory already exists. the exist_ok parameter exists not until
        # python3.2
        pass
    with open(os.path.join(base, *path), 'wt', encoding='utf-8') as f:
        if content is None:
            # With yaml.dump is not compatible in python2 and python3
            f.write(u'{"path": "%s", "unicode": "%s"}' % (
                os.path.join(*path),    # this content is predictable
                u"äæo≤»で"))            # some unicode test data
        else:
            f.write(content)

def set_(iterable):
    return set((s for s in iterable
                if not s.endswith('.pyc') and s != '__pycache__'))


@contextlib.contextmanager
def captured_output(stream_name):
    if str is bytes:
        # Python2: setuptools gives non-unicode output, so we have to
        # supply a binary stream:
        from io import BytesIO as StringIO
    else:
        # Python3: str is unicode and everything is alright.
        from io import StringIO
    orig_stdout = getattr(sys, stream_name)
    setattr(sys, stream_name, StringIO())
    try:
        yield getattr(sys, stream_name)
    finally:
        setattr(sys, stream_name, orig_stdout)


# common test code

class Common(object):
    def setUp(self):
        self.mod = 'dummy_mod_124'
        self.base = tempfile.mkdtemp()
        self.path = os.path.join(self.base, self.mod)
        create_test_file(self.path, ['__init__.py'], u'')
        create_test_file(self.path, ['a.yml'])
        create_test_file(self.path, ['subdir', 'b.yml'])

    def tearDown(self):
        gc.collect()
        shutil.rmtree(self.base)

    def test_open(self):
        with self.res.open('a.yml', 'utf-8') as f:
            self.assertEqual(
                yaml.load(f.read())['path'],
                'a.yml')
        with self.res.get('subdir/b.yml').open(encoding='utf-8') as f:
            self.assertEqual(
                    yaml.load(f.read())['path'],
                    os.path.join('subdir', 'b.yml'))

    def test_list(self):
        self.assertEqual(
                set_(self.res.listdir()),
                set(('__init__.py', 'a.yml', 'subdir')))
        self.assertEqual(
                set(self.res.listdir('subdir')),
                set(('b.yml',)))
        self.assertEqual(
                set(self.res.get('subdir').listdir()),
                set(('b.yml',)))

    def test_provider(self):
        self.assertEqual(
                set_(self.res.get('subdir').provider().listdir()),
                set(('__init__.py', 'a.yml', 'subdir')))
        self.assertEqual(
                set(self.res.get(['subdir', 'b.yml']).provider().listdir()),
                set(('b.yml',)))

    def test_filter(self):
        self.assertEqual(
                set(self.res.listdir_filter(ext='.txt')),
                set())
        self.assertEqual(
                set(self.res.listdir_filter(ext='.yml')),
                set(('a.yml',)))

    def test_load(self):
        self.assertEqual(
                yaml.load(self.res.load('a.yml', 'utf-8'))['path'],
                'a.yml')
        self.assertEqual(
                yaml.load(self.res.get('subdir').load('b.yml', 'utf-8'))['path'],
                os.path.join('subdir', 'b.yml'))

    def test_yaml(self):
        self.assertEqual(
                self.res.yaml('a.yml')['path'],
                'a.yml')
        self.assertEqual(
                self.res.get(['subdir', 'b.yml']).yaml()['path'],
                os.path.join('subdir', 'b.yml'))


# test cases
class TestPackageResource(Common, unittest.TestCase):
    def setUp(self):
        super(TestPackageResource, self).setUp()
        sys.path.append(self.base)
        self.res = PackageResource(self.mod)

    def tearDown(self):
        del self.res
        del sys.modules[self.mod]
        sys.path.remove(self.base)
        super(TestPackageResource, self).tearDown()

    def test_filename(self):
        with self.res.filename('a.yml') as filename:
            with open(filename, encoding='utf-8') as f:
                self.assertEqual(
                        yaml.load(f.read())['path'],
                        'a.yml')
        self.assertTrue(os.path.exists(filename))
        with self.res.get(['subdir', 'b.yml']).filename() as filename:
            with open(filename, encoding='utf-8') as f:
                self.assertEqual(
                        yaml.load(f.read())['path'],
                        'subdir/b.yml')
        self.assertTrue(os.path.exists(filename))

class TestEggResource(Common, unittest.TestCase):
    def setUp(self):
        super(TestEggResource, self).setUp()
        cwd = os.getcwd()
        os.chdir(self.base)
        with captured_output('stdout'):
            with captured_output('stderr'):
                setuptools.setup(
                    name=self.mod,
                    packages=[self.mod],
                    script_args=['bdist_egg', '--quiet'],
                    package_data={self.mod:[
                        'a.yml',
                        os.path.join('subdir', 'b.yml')]})
        os.chdir(cwd)
        self.eggs = os.listdir(os.path.join(self.base, 'dist'))
        for egg in self.eggs:
            sys.path.append(os.path.join(self.base, 'dist', egg))
        self.res = PackageResource(self.mod)

    def tearDown(self):
        del self.res
        del sys.modules[self.mod]
        for egg in self.eggs:
            sys.path.remove(os.path.join(self.base, 'dist', egg))
        super(TestEggResource, self).tearDown()

    def test_filename(self):
        with self.res.filename('a.yml') as filename:
            with open(filename, encoding='utf-8') as f:
                self.assertEqual(
                        yaml.load(f.read())['path'],
                        'a.yml')
        self.assertFalse(os.path.exists(filename))
        with self.res.get(['subdir', 'b.yml']).filename() as filename:
            with open(filename, encoding='utf-8') as f:
                self.assertEqual(
                        yaml.load(f.read())['path'],
                        'subdir/b.yml')
        self.assertFalse(os.path.exists(filename))
        # The resource should be accessible again, even though the file was
        # deleted when exiting the context manager:
        with self.res.get(['subdir', 'b.yml']).filename() as filename:
            with open(filename, encoding='utf-8') as f:
                self.assertEqual(
                        yaml.load(f.read())['path'],
                        'subdir/b.yml')
        self.assertFalse(os.path.exists(filename))

class TestFileResource(Common, unittest.TestCase):
    def setUp(self):
        super(TestFileResource, self).setUp()
        self.res = FileResource(self.path)

    def tearDown(self):
        del self.res
        super(TestFileResource, self).tearDown()

    def test_filename(self):
        with self.res.filename('a.yml') as filename:
            self.assertEqual(
                    filename,
                    os.path.join(self.path, 'a.yml'))
        with self.res.get(['subdir', 'b.yml']).filename() as filename:
            self.assertEqual(
                    filename,
                    os.path.join(self.path, 'subdir', 'b.yml'))


class TestCouchResource(unittest.TestCase):
    """TODO."""
    pass


if __name__ == '__main__':
    unittest.main()

