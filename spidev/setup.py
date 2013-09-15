from distutils.core import setup
from Cython.Build import cythonize

setup(
    name="spidev",
    ext_modules=cythonize('*.pyx')
)
