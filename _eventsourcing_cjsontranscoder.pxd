# cython: language_level=3, boundscheck=False, wraparound=False, nonecheck=False, binding=False
from cpython.object cimport PyTypeObject

cdef class CTranscoding:
    cdef object type
    cdef str name
    cpdef object encode(self, object obj)
    cpdef object decode(self, object data)
