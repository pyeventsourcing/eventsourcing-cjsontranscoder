# -*- coding: utf-8 -*-
from eventsourcing.application import Application
from eventsourcing.domain import Aggregate, event
from eventsourcing.persistence import Transcoding
from eventsourcing.tests.persistence import MyInt, MyStr

from eventsourcing_cjsontranscoder import (
    CDatetimeAsISO,
    CJSONTranscoder,
    CTranscoding,
    CTupleAsList,
    CUUIDAsHex,
)


# Subclass of Cython extension type in pure Python.
class CMyIntAsInt(CTranscoding):
    def type(self):
        return MyInt

    def name(self):
        return "myint_as_int"

    def encode(self, obj):
        return int(obj)

    def decode(self, data):
        return MyInt(data)


# Subclass of Transcoding class.
class MyStrAsStr(Transcoding):
    type = MyStr
    name = "mystr_as_str"

    def encode(self, obj):
        return str(obj)

    def decode(self, data):
        return MyStr(data)


class DogSchool(Application):
    def construct_transcoder(self):
        transcoder = CJSONTranscoder()
        self.register_transcodings(transcoder)
        return transcoder

    def register_transcodings(self, transcoder):
        transcoder.register(CUUIDAsHex())
        transcoder.register(CDatetimeAsISO())
        transcoder.register(CTupleAsList())
        transcoder.register(CMyIntAsInt())
        transcoder.register(MyStrAsStr())

    def register_dog(self, name, age):
        dog = Dog(name, age)
        self.save(dog)
        return dog.id

    def add_trick(self, dog_id, trick):
        dog = self.repository.get(dog_id)
        dog.add_trick(trick)
        self.save(dog)

    def update_age(self, dog_id, age):
        dog = self.repository.get(dog_id)
        dog.update_age(age)
        self.save(dog)

    def get_dog(self, dog_id):
        dog = self.repository.get(dog_id)
        return {"name": dog.name, "tricks": tuple(dog.tricks), "age": dog.age}


class Dog(Aggregate):
    @event("Registered")
    def __init__(self, name, age):
        self.name = name
        self.age = age
        self.tricks = []

    @event("TrickAdded")
    def add_trick(self, trick):
        self.tricks.append(trick)

    @event("AgeUpdated")
    def update_age(self, age):
        self.age = age


def test_dog_school():
    # Construct application object.
    school = DogSchool()

    # Evolve application state.
    dog_id = school.register_dog("Fido", 2)
    school.add_trick(dog_id, "roll over")
    school.add_trick(dog_id, "play dead")
    school.update_age(dog_id, 5)

    # Query application state.
    dog = school.get_dog(dog_id)
    assert dog["name"] == "Fido"
    assert type(dog["name"]) is str
    assert dog["tricks"] == ("roll over", "play dead")
    assert dog["age"] == 5
    assert type(dog["age"]) is int

    # Evolve application state.
    dog_id = school.register_dog(MyStr("Fido"), MyInt(2))
    school.add_trick(dog_id, MyStr("roll over"))
    school.add_trick(dog_id, MyStr("play dead"))
    school.update_age(dog_id, MyInt(5))

    # Query application state.
    dog = school.get_dog(dog_id)
    assert dog["name"] == MyStr("Fido")
    assert dog["tricks"] == (MyStr("roll over"), MyStr("play dead"))
    assert dog["age"] == MyInt(5)

    # Select notifications.
    notifications = school.notification_log.select(start=1, limit=10)
    assert len(notifications) == 8
