from distutils.core import setup
from distutils.extension import Extension
#from Cython.Build import cythonize
from Cython.Distutils import build_ext
import numpy as np

setup(
    name="nanomixer",
    ext_modules=[Extension('wireformat', ['wireformat.pyx'], include_dirs=[np.get_include()])],
    cmdclass={'build_ext': build_ext}
)
