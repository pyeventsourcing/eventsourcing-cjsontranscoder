# -*- coding: utf-8 -*-
import os
from distutils.command.build_ext import build_ext

from Cython.Build import cythonize


# This function will be executed in setup.py:
def build(setup_kwargs):
    # The file you want to compile
    extensions = [
        "_eventsourcing_cjsontranscoder.pyx",
    ]

    # gcc arguments hack: enable optimizations
    os.environ["CFLAGS"] = "-O3"

    # Build
    setup_kwargs.update(
        {
            "ext_modules": cythonize(
                extensions,
                language_level=3,
                compiler_directives={"linetrace": True},
            ),
            "cmdclass": {"build_ext": build_ext},
        }
    )
