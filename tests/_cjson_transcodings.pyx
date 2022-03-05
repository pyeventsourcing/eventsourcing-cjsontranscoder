# cython: language_level=3, boundscheck=False, wraparound=False, nonecheck=False, binding=False
from eventsourcing.tests.persistence import (
    CustomType1,
    CustomType2,
    MyDict,
    MyInt,
    MyList,
    MyStr,
)

from _eventsourcing_cjsontranscoder cimport CTranscoding


cdef class CCustomType1AsDict(CTranscoding):
    cpdef object type(self):
        return CustomType1

    cpdef str name(self):
        return "custom_type1_as_dict"

    cpdef object encode(self, object obj):
        return obj.value

    cpdef object decode(self, object data):
        return CustomType1(value=data)


cdef class CCustomType2AsDict(CTranscoding):
    cpdef object type(self):
        return CustomType2

    cpdef str name(self):
        return "custom_type2_as_dict"

    cpdef object encode(self, object obj):
        return obj.value

    cpdef object decode(self, object data):
        return CustomType2(data)


cdef class CMyDictAsDict(CTranscoding):
    cpdef object type(self):
        return MyDict

    cpdef str name(self):
        return "mydict"

    cpdef object encode(self, object obj):
        return obj.copy()

    cpdef object decode(self, object data):
        return MyDict(data)


cdef class CMyListAsList(CTranscoding):
    cpdef object type(self):
        return MyList

    cpdef str name(self):
        return "mylist"

    cpdef object encode(self, object obj):
        return list(obj)

    cpdef object decode(self, object data):
        return MyList(data)


cdef class CMyStrAsStr(CTranscoding):
    cpdef object type(self):
        return MyStr

    cpdef str name(self):
        return "mystr"

    cpdef object encode(self, object obj):
        return str(obj)

    cpdef object decode(self, object data):
        return MyStr(data)


cdef class CMyIntAsInt(CTranscoding):
    cpdef object type(self):
        return MyInt

    cpdef str name(self):
        return "myint"

    cpdef object encode(self, object obj):
        return int(obj)

    cpdef object decode(self, object data):
        return MyInt(data)