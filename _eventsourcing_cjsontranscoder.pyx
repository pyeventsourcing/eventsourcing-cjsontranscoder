# cython: language_level=3, boundscheck=False, wraparound=False, nonecheck=False, binding=False
from datetime import datetime
from decimal import Decimal
from json import JSONDecoder
from json.encoder import encode_basestring
from typing import cast
from uuid import UUID

from eventsourcing.persistence import Transcoding

NoneType = type(None)

from cpython.dict cimport PyDict_GetItem, PyDict_Items
from cpython.exc cimport PyErr_SetString
from cpython.list cimport PyList_Append, PyList_GET_ITEM, PyList_Size
from cpython.mem cimport PyMem_Free, PyMem_Malloc
from cpython.object cimport PyObject, PyTypeObject
from cpython.ref cimport Py_DECREF, Py_INCREF
from cpython.tuple cimport PyTuple_GET_ITEM
from cpython.unicode cimport PyUnicode_AsUTF8String, PyUnicode_Join


cdef PyObject * LIST_START = <PyObject *>"["
cdef PyObject * LIST_FINISH = <PyObject *>"]"

cdef PyObject * DICT_START = <PyObject *>"{"
cdef PyObject * DICT_FINISH = <PyObject *>"}"

cdef str COMMA_SEPARATOR = ","

cdef PyTypeObject * TYPE_BOOL = <PyTypeObject *>bool
cdef PyTypeObject * TYPE_STR = <PyTypeObject *>str
cdef PyTypeObject * TYPE_INT = <PyTypeObject *>int
cdef PyTypeObject * TYPE_FLOAT = <PyTypeObject *>float
cdef PyTypeObject * TYPE_NONE = <PyTypeObject *>NoneType
cdef PyTypeObject * TYPE_LIST = <PyTypeObject *>list
cdef PyTypeObject * TYPE_DICT = <PyTypeObject *>dict

cdef PyObject * BOOL_TRUE = <PyObject *>True
cdef PyObject * BOOL_FALSE = <PyObject *>False
cdef PyObject * PY_ERROR = <PyObject *>BaseException


cdef class CJSONTranscoder:
    cdef dict types
    cdef dict names
    cdef object decoder

    def __init__(self):
        self.types = {}
        self.names = {}
        self.decoder = JSONDecoder()

    cpdef register(self, transcoding):
        """
        Registers given transcoding with the transcoder.
        """
        if isinstance(transcoding, Transcoding):
            transcoding = CTranscodingAdaptor(transcoding)
        self._register(transcoding)

    cdef void _register(self, CTranscoding transcoding):
        self.types[transcoding.type] = transcoding
        self.names[transcoding.name] = transcoding

    cpdef bytes encode(self, object obj):
        """
        Encodes given object to JSON bytes.
        """
        cdef list output = list()

        cdef EncoderContext * ctx = <EncoderContext *>PyMem_Malloc(sizeof(EncoderContext))
        ctx.output = <PyObject *>output
        ctx.types = <PyObject *>self.types
        ctx.frame = NULL_FRAME

        # Visit the root node.
        visit_node(<PyObject *>obj, ctx)

        # Iterate over the frames.
        while ctx.frame != NULL_FRAME:
            visit_frame(ctx)

        PyMem_Free(ctx)

        # Join output strings and encode unicode as bytes.
        return PyUnicode_AsUTF8String(PyUnicode_Join("", output))

    cpdef object decode(self, bytes data):
        """
        Encodes given JSON bytes to original object.
        """
        cdef object obj = self.decoder.decode(data.decode('utf8'))
        cdef object obj_type = type(obj)
        cdef list stack = []
        cdef int stack_pointer = 0
        cdef list frame = None
        cdef dict dict_obj
        cdef object dict_key
        cdef list list_obj
        cdef int list_index
        cdef object value
        cdef object value_type

        cdef CTranscoding transcoding
        cdef object transcoded_type
        cdef object transcoded_data

        if obj_type is dict:
            stack.append([obj, None, None])
        elif obj_type is list:
            stack.append([obj, None, None])

        while stack_pointer < len(stack):
            frame = stack[stack_pointer]
            stack_pointer += 1
            obj = frame[0]
            obj_type = type(obj)
            if obj_type is dict:
                for dict_key, value in (<dict> obj).items():
                    value_type = type(value)
                    if value_type is dict or value_type is list:
                        stack.append([value, obj, dict_key])

            elif obj_type is list:
                list_obj = <list> obj
                for list_index in range(len(list_obj)):
                    value = list_obj[list_index]
                    value_type = type(value)
                    if value_type is dict or value_type is list:
                        stack.append([value, obj, list_index])

        while stack_pointer > 0:
            stack_pointer -= 1
            frame = stack[stack_pointer]
            obj = frame[0]
            if type(obj) is dict:
                dict_obj = <dict> obj
                if len(dict_obj) == 2:
                    try:
                        transcoded_type = dict_obj["_type_"]
                    except KeyError:
                        pass
                    else:
                        try:
                            transcoded_data = dict_obj["_data_"]
                        except KeyError:
                            pass
                        else:
                            try:
                                transcoding = self.names[transcoded_type]
                            except KeyError:
                                raise TypeError(
                                    f"Data serialized with name '{cast(str, transcoded_type)}' is not "
                                    "deserializable. Please register a "
                                    "custom transcoding for this type."
                                )
                            else:
                                obj = transcoding.decode(transcoded_data)
                                if frame[1] is not None:
                                    frame[1][frame[2]] = obj
        return obj


ctypedef PyObject *(*get_next_child_func)(EncoderContext * ctx) except NULL


cdef struct EncoderContext:
    PyObject * output
    PyObject * types
    NodeFrame * frame


cdef struct NodeFrame:
    NodeFrame * parent
    PyObject * node
    PyObject * start_char
    PyObject * finish_char
    PyObject * children
    Py_ssize_t node_len
    Py_ssize_t i_child
    get_next_child_func get_next_child


cdef void new_list_frame(PyObject * node, EncoderContext * ctx):
    cdef NodeFrame * frame = <NodeFrame *>PyMem_Malloc(sizeof(NodeFrame))
    Py_INCREF(<object>node)
    frame.node = node
    frame.parent = ctx.frame
    ctx.frame = frame
    frame.children = node
    frame.node_len = PyList_Size(<list>node)
    frame.i_child = 0
    frame.get_next_child = get_next_list_child
    frame.start_char = LIST_START
    frame.finish_char = LIST_FINISH


cdef NodeFrame * NULL_FRAME = <NodeFrame *>PyMem_Malloc(sizeof(NodeFrame))


cdef PyObject * get_next_list_child(EncoderContext * ctx) except NULL:
    return <PyObject *>PyList_GET_ITEM(<object>ctx.frame.children, ctx.frame.i_child)


cdef void new_dict_frame(PyObject * node, EncoderContext * ctx):
    cdef NodeFrame * frame = <NodeFrame *>PyMem_Malloc(sizeof(NodeFrame))
    cdef list dict_items = PyDict_Items(<object>node)
    Py_INCREF(dict_items)

    frame.node = node
    frame.parent = ctx.frame
    ctx.frame = frame
    frame.children = <PyObject *>dict_items
    frame.node_len = PyList_Size(dict_items)
    frame.i_child = 0
    frame.get_next_child = get_next_dict_child
    frame.start_char = DICT_START
    frame.finish_char = DICT_FINISH


cdef PyObject * get_next_dict_child(EncoderContext * ctx) except NULL:
    cdef PyObject * key_and_value = PyList_GET_ITEM(<list>ctx.frame.children, ctx.frame.i_child)
    append_output(ctx.output, '"')
    append_output(ctx.output, <object>PyTuple_GET_ITEM(<tuple>key_and_value, 0))
    append_output(ctx.output, '":')
    return PyTuple_GET_ITEM(<tuple>key_and_value, 1)


cdef void new_custom_type_frame(PyObject * node, EncoderContext * ctx):
    cdef NodeFrame * frame = <NodeFrame *>PyMem_Malloc(sizeof(NodeFrame))
    frame.node = node
    frame.parent = ctx.frame
    ctx.frame = frame
    frame.children = NULL
    frame.node_len = 1
    frame.i_child = 0
    frame.get_next_child = get_next_custom_type_child
    frame.start_char = DICT_START
    frame.finish_char = DICT_FINISH


cdef str NOT_SERIALIZABLE = "Object of type %s is not serializable. Please define \
and register a custom transcoding for this type."

cdef PyObject * get_next_custom_type_child(EncoderContext * ctx) except NULL:
    cdef CTranscoding transcoding
    cdef object encoded_obj
    cdef bytes error_msg
    cdef void * dict_item = PyDict_GetItem(<object>ctx.types, <object>ctx.frame.node.ob_type)
    if dict_item == NULL:
        # error_msg = NOT_SERIALIZABLE % <object>ctx.frame.node.ob_type
        # raise TypeError(error_msg)
        error_msg = (NOT_SERIALIZABLE % <object>ctx.frame.node.ob_type).encode('utf8')
        PyErr_SetString(TypeError, <char *>error_msg)
        return NULL
    else:
        transcoding = <CTranscoding>dict_item
        append_output(ctx.output, '"_type_":"')
        append_output(ctx.output, transcoding.name)
        append_output(ctx.output, '","_data_":')
        encoded_obj = transcoding.encode(<object>ctx.frame.node)
        ctx.frame.children = <PyObject *>encoded_obj
        Py_INCREF(encoded_obj)
        return ctx.frame.children


cdef int visit_node(PyObject * node, EncoderContext * ctx) except -1:
    # Decide whether to start a new frame for a
    # collection or append output for a leaf node.
    cdef PyTypeObject * node_type = node.ob_type
    if node_type is TYPE_LIST:
        new_list_frame(node, ctx)
    elif node_type is TYPE_DICT:
        new_dict_frame(node, ctx)
    elif node_type == TYPE_STR:
        append_output(ctx.output, encode_basestring(<object>node))
    elif node_type is TYPE_INT:
        append_output(ctx.output, str(<object>node))
    elif node_type is TYPE_BOOL:
        if <object>node is True:
            append_output(ctx.output, "true")
        else:
            append_output(ctx.output, "false")
    elif node_type is TYPE_FLOAT:
        append_output(ctx.output, str(<object> node))
    elif node_type is TYPE_NONE:
        append_output(ctx.output, "null")
    else:
        new_custom_type_frame(node, ctx)


cdef int visit_frame(EncoderContext * ctx) except -1:
    cdef NodeFrame * frame = ctx.frame
    cdef NodeFrame * parent_frame = NULL_FRAME
    cdef PyObject * next_child

    # Check if this is the first node.
    if frame.i_child == 0:
        # Start output for this ctx.frame.
        append_output(ctx.output, <object>frame.start_char)

    # Loop over the child nodes until we get a new ctx.frame.
    while frame == ctx.frame and frame.i_child < frame.node_len:

        # Check if we are continuing after the first child.
        if frame.i_child > 0:
            # Continue output for this frame's children.
            append_output(ctx.output, COMMA_SEPARATOR)

        # Visit the next child node.
        next_child = frame.get_next_child(ctx)
        if next_child == NULL:
            # There was an error, so free all allocated memory
            # decrement all incremented references, and break.
            while frame != NULL_FRAME:
                parent_frame = frame.parent
                Py_DECREF(<object> frame.children)
                PyMem_Free(frame)
                frame = parent_frame
            break

        else:
            visit_node(next_child, ctx)
            frame.i_child += 1


    # Check if this frame has been completed.
    if frame == ctx.frame and frame.i_child == frame.node_len:
        # We aren't going to visit a child frame, and we have
        # visited all nodes in this frame, so finish output,
        # free allocated memory, decrement incremented references,
        # and return to parent frame.
        append_output(ctx.output, <object>ctx.frame.finish_char)
        parent_frame = frame.parent
        Py_DECREF(<object>frame.children)
        PyMem_Free(ctx.frame)
        ctx.frame = parent_frame


cdef void append_output(PyObject * output, str s):
    PyList_Append(<object> output, s)


cdef class CTranscoding:
    """
    Base class for transcoding objects.
    """
    cpdef object encode(self, object obj):
        raise NotImplementedError()

    cpdef object decode(self, object data):
        raise NotImplementedError()


cdef class CTranscodingAdaptor(CTranscoding):
    """
    Adaptor for Transcoding objects.
    """
    cdef object transcoding

    def __init__(self, transcoding: Transcoding):
        self.transcoding = transcoding
        self.type = transcoding.type
        self.name = transcoding.name

    cpdef object encode(self, object obj):
        return self.transcoding.encode(obj)

    cpdef object decode(self, object data):
        return self.transcoding.decode(data)


cdef class CTupleAsList(CTranscoding):
    """
    Transcoding that represents :class:`tuple` objects as lists.
    """
    def __init__(self):
        self.type = tuple
        self.name = "tuple_as_list"

    cpdef object encode(self, object obj):
        return [i for i in obj]

    cpdef object decode(self, object data):
        return tuple(data)


cdef class CDatetimeAsISO(CTranscoding):
    """
    Transcoding that represents :class:`datetime` objects as ISO strings.
    """
    def __init__(self):
        self.type = datetime
        self.name = "datetime_iso"

    cpdef object encode(self, object obj):
        return obj.isoformat()

    cpdef object decode(self, object data):
        return datetime.fromisoformat(data)


cdef class CUUIDAsHex(CTranscoding):
    """
    Transcoding that represents :class:`UUID` objects as hex values.
    """
    def __init__(self):
        self.type = UUID
        self.name = "uuid_hex"

    cpdef object encode(self, object obj):
        return obj.hex

    cpdef object decode(self, object data):
        return UUID(data)


cdef class CDecimalAsStr(CTranscoding):
    """
    Transcoding that represents :class:`Decimal` objects as strings.
    """
    def __init__(self):
        self.type = Decimal
        self.name = "decimal_str"

    cpdef object encode(self, object obj):
        return str(obj)

    cpdef object decode(self, object data):
        return Decimal(data)
