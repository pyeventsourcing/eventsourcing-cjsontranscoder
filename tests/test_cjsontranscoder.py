# -*- coding: utf-8 -*-
import timeit
from copy import copy
from decimal import Decimal
from time import sleep
from uuid import NAMESPACE_URL, UUID, uuid5

from eventsourcing.domain import DomainEvent
from eventsourcing.persistence import DatetimeAsISO, JSONTranscoder, UUIDAsHex
from eventsourcing.tests.persistence import (
    CustomType1,
    CustomType1AsDict,
    CustomType2,
    CustomType2AsDict,
    MyInt,
    MyStr,
    TranscoderTestCase,
)
from orjson import orjson

from eventsourcing_cjsontranscoder import (
    CDatetimeAsISO,
    CDecimalAsStr,
    CJSONTranscoder,
    CTupleAsList,
    CUUIDAsHex,
)
from tests._cjson_transcodings import (
    CCustomType1AsDict,
    CCustomType2AsDict,
    CMyDictAsDict,
    CMyIntAsInt,
    CMyListAsList,
    CMyStrAsStr,
)


class TestCJSONTranscoder(TranscoderTestCase):
    def construct_transcoder(self):
        transcoder = CJSONTranscoder()
        transcoder.register(CTupleAsList())
        transcoder.register(CDatetimeAsISO())
        transcoder.register(CUUIDAsHex())
        transcoder.register(CDecimalAsStr())
        transcoder.register(CCustomType1AsDict())
        transcoder.register(CCustomType2AsDict())
        transcoder.register(CMyDictAsDict())
        transcoder.register(CMyListAsList())
        transcoder.register(CMyIntAsInt())
        transcoder.register(CMyStrAsStr())
        return transcoder

    def test_custom_type_error(self):
        super().test_custom_type_error()

    def test_str(self):
        super().test_str()

    def test_str_subclass(self):
        transcoder = self.construct_transcoder()
        obj = MyStr("buddy")
        # Weirdly __str__ for str isn't the same as __repr__,
        # but then if it were, there wouldn't be a way to get
        # the actual str (without .encode().decode()). Even
        # str.__str__() doesn't escape the subclass __str__
        # which seems weird. See also test_int_subclass().
        self.assertEqual("buddy", str(obj))
        self.assertEqual("MyStr('buddy')", repr(obj))
        self.assertEqual(MyStr("buddy"), copy(obj))
        self.assertEqual("buddy", obj.encode().decode())
        data = transcoder.encode(obj)
        self.assertEqual(data, b'{"_type_":"mystr","_data_":"buddy"}')
        _copy = transcoder.decode(data)
        self.assertEqual(obj, _copy)

    def test_none_type(self):
        transcoder = self.construct_transcoder()
        obj = None
        data = transcoder.encode(obj)
        copy = transcoder.decode(data)
        self.assertEqual(obj, copy)

    def test_list(self):
        transcoder = self.construct_transcoder()
        obj = [1, 2]
        data = transcoder.encode(obj)
        self.assertEqual(data, b"[1,2]")
        copy = transcoder.decode(data)
        self.assertEqual(obj, copy)
        super().test_list()

    def test_dict(self):
        super().test_dict()

        # Dict with non-ascii key and value.
        obj = {"🐈": "哈哈"}
        data = self.transcoder.encode(obj)
        self.assertEqual(data, b'{"\xf0\x9f\x90\x88":"\xe5\x93\x88\xe5\x93\x88"}')
        self.assertEqual(obj, self.transcoder.decode(data))

    def test_dict_subclass(self):
        super().test_dict_subclass()

    def test_tuple(self):
        super().test_tuple()

    def test_int(self):
        transcoder = self.construct_transcoder()
        obj = 11111111111111111111111111111111111111111111
        data = transcoder.encode(obj)
        self.assertEqual(data, b"11111111111111111111111111111111111111111111")
        copy = transcoder.decode(data)
        self.assertEqual(obj, copy)

        # It isn't possible to encode very large integers with orjson.
        with self.assertRaises(TypeError) as cm:
            orjson.dumps(11111111111111111111111111111111111)
        self.assertEqual(cm.exception.args[0], "Integer exceeds 64-bit range")

    def test_int_subclass(self):
        transcoder = self.construct_transcoder()
        obj = MyInt(11111111111111111111111111111111111)
        # This is also weird, because if __str__ is defined on subclass
        # to give MyInt(c) by calling super()__str__() to give "c" then
        # str(MyInt(c)) somehow gives "MyInt(MyInt(c)" although
        # int.__str__(MyInt(c)) gives "MyInt(c)" so presumably it should
        # recurse infinitely? See also test_str_subclass().
        self.assertEqual("MyInt(11111111111111111111111111111111111)", str(obj))
        self.assertEqual("MyInt(11111111111111111111111111111111111)", repr(obj))
        data = transcoder.encode(obj)
        self.assertEqual(
            data, b'{"_type_":"myint","_data_":11111111111111111111111111111111111}'
        )
        copy = transcoder.decode(data)
        self.assertEqual(obj, copy)

    def test_bool(self):
        transcoder = self.construct_transcoder()
        obj = True
        data = transcoder.encode(obj)
        copy = transcoder.decode(data)
        self.assertEqual(obj, copy)

        obj = False
        data = transcoder.encode(obj)
        copy = transcoder.decode(data)
        self.assertEqual(obj, copy)

    def test_float(self):
        transcoder = self.construct_transcoder()
        obj = 3.141592653589793
        data = transcoder.encode(obj)
        self.assertEqual(data, b"3.141592653589793")
        copy = transcoder.decode(data)
        self.assertEqual(obj, copy)

        obj = 211.7
        data = transcoder.encode(obj)
        self.assertEqual(data, b"211.7")
        copy = transcoder.decode(data)
        self.assertEqual(obj, copy)

    def test_decimal(self):
        transcoder = self.construct_transcoder()
        obj = Decimal("3.141592653589793")
        data = transcoder.encode(obj)
        self.assertEqual(data, b'{"_type_":"decimal_str","_data_":"3.141592653589793"}')
        copy = transcoder.decode(data)
        self.assertEqual(obj, copy)

    def test_performance(self):
        transcoder = self.construct_transcoder()
        self._test_performance(transcoder)
        sleep(0.1)
        transcoder = JSONTranscoder()
        transcoder.register(DatetimeAsISO())
        transcoder.register(UUIDAsHex())
        transcoder.register(CustomType1AsDict())
        transcoder.register(CustomType2AsDict())
        self._test_performance(transcoder)
        print("")
        print("")
        print("")
        sleep(0.1)

    def _test_performance(self, transcoder):

        obj = {
            "originator_id": uuid5(NAMESPACE_URL, "some_id"),
            "originator_version": 123,
            "timestamp": DomainEvent.create_timestamp(),
            "a_str": "hello",
            "b_int": 1234567,
            "c_tuple": (1, 2, 3, 4, 5, 6, 7),
            "d_list": [1, 2, 3, 4, 5, 6, 7],
            "e_dict": {"a": 1, "b": 2, "c": 3},
            "f_valueobj": CustomType2(
                CustomType1(UUID("b2723fe2c01a40d2875ea3aac6a09ff5"))
            ),
        }

        data = transcoder.encode(obj)

        # Warm up.
        timeit.timeit(lambda: transcoder.encode(obj), number=100)

        number = 10000
        duration = timeit.timeit(lambda: transcoder.encode(obj), number=number)
        print(
            f"{transcoder.__class__.__name__} encode:"
            f" {1000000 * duration / number:.1f} μs"
        )

        data = transcoder.encode(obj)
        transcoder.decode(data)
        timeit.timeit(lambda: transcoder.decode(data), number=100)

        duration = timeit.timeit(lambda: transcoder.decode(data), number=number)
        print(
            f"{transcoder.__class__.__name__} decode:"
            f" {1000000 * duration / number:.1f} μs"
        )


del TranscoderTestCase
