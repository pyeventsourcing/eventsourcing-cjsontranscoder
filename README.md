# Welcome to the CJSONTranscoder project

This package provides a `CJSONTranscoder` class for use with
the Python eventsourcing library, that uses Cython for greater
speed, but more importantly for transcoding of `tuple` objects
and subclasses of `str`, `int`, `float`, `dict` and `tuple`.


## Installation

Use pip to install the [stable distribution](https://pypi.org/project/eventsourcing-cjsontranscoder/)
from the Python Package Index.

    $ pip install eventsourcing_cjsontranscoder

It is recommended to install Python packages into a Python virtual environment.

This package uses Cython, so relevant build tools may need to be
installed before this package can be installed successfully.


## Synopsis

```python
>>> from eventsourcing_cjsontranscoder import CJSONTranscoder, CTupleAsList
>>> t = CJSONTranscoder()
>>> t.register(CTupleAsList())
>>> d = t.encode((1, 2, 3))
>>> d
b'{"_type_":"tuple_as_list","_data_":[1,2,3]}'
>>> t.decode(d)
(1, 2, 3)
```

## Features

Most importantly, `CJSONTranscoder` supports custom transcoding of instances
of `tuple` and subclasses of `str`, `int`, `float`, `dict` and `tuple`. This is an
important improvement on the core library's `JSONTranscoder` class which,
converts `tuple` to `list` and loses type information for subclasses of
`str`, `int`, `float`, `list`, `dict` and `tuple`. That is because of the way Python's
`JSONEncoder` class functions, which doesn't pass through subclasses
of these types to the `default` method. This is important in a domain-driven
design, in which the ubiquitous language may be expressed as subclasses of
these types.

The `CJSONTranscoder` is also faster than `JSONTranscoder`, encoding approximately
x2 faster. This is less important than the preservation of type information (see above)
because latency in your application will usually be dominated by database interactions.
However, it's nice that it's not slower.

| class           |  encode |  decode |
|-----------------|--------:|--------:|
| CJSONTranscoder |  9.3 μs | 12.9 μs |
| JSONTranscoder  | 15.0 μs | 13.5 μs |

The above benchmark was performed with Python 3.10 on GitHub using the following
object, which is perhaps representative of the state of a domain event in an
event-sourced application.

```python
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

```

## Custom Transcodings

You can register subclasses of the `Transcoding` class with the `CJSONTranscoder`.
This is the easiest option if you have already defined transcodings for in your
project, but it is also the slowest option.

Alternatively, you can define custom transcodings in pure Python code by subclassing
the Cython extension type `CTranscoding`. The prefix `C` is used to distinguish
these classes from the `Transcoding` classes provided by the core Python
eventsourcing library. For example, consider the classes `MyInt` and `CMyIntAsInt`
below.

```python
class MyInt(int):
    def __repr__(self):
        return f"{type(self).__name__}({super().__repr__()})"

    def __eq__(self, other):
        return type(self) == type(other) and super().__eq__(other)
```

You can define a custom transcoding for `MyInt` as a normal Python class in a
normal Python module (`.py` file) using the `CTranscoding` class.

```python
from eventsourcing_cjsontranscoder import CTranscoding

class CMyIntAsInt(CTranscoding):
    def type(self):
        return MyInt

    def name(self):
        return "myint_as_int"

    def encode(self, obj):
        return int(obj)

    def decode(self, data):
        return MyInt(data)
```

Alternatively for slightly greater transcoding performance, you can define a
custom transcoding for `MyInt` as a Cython extension type in a Cython module
(`.pyx` file) using the `CTranscoding` extension type.

```cython
from _eventsourcing_cjsontranscoder cimport CTranscoding

from my_domain_model import MyInt

cdef class CMyIntAsInt(CTranscoding):
    cpdef object type(self):
        return MyInt

    cpdef str name(self):
        return "myint_as_int"

    cpdef object encode(self, object obj):
        return int(obj)

    cpdef object decode(self, object data):
        return MyInt(data)
```

If you define your transcodings in a Cython module, you will need to build it
before you can use your transcodings. You can build your module in place with
the following command.

```commandline
$ cythonize -i my_transcodings.pyx
```

If you are distributing your code, you will also need to configure
your distribution to build the Cython module when your code is installed.

See this project's repository, the Cython documentation, and examples online
for more information about Cython and building Cython modules.


## Using the CJSONTranscoder

To use the `CJSONTranscoder` class in a Python eventsourcing application
object, override  the `construct_transcoder()` and `register_transcodings()`
methods.

```python

from eventsourcing.application import Application
from eventsourcing.domain import Aggregate, event
from eventsourcing_cjsontranscoder import (
    CDatetimeAsISO,
    CTupleAsList,
    CUUIDAsHex,
    CJSONTranscoder,
)


class DogSchool(Application):
    def construct_transcoder(self):
        transcoder = CJSONTranscoder()
        self.register_transcodings(transcoder)
        return transcoder

    def register_transcodings(self, transcoder):
        transcoder.register(CDatetimeAsISO())
        transcoder.register(CTupleAsList())
        transcoder.register(CUUIDAsHex())
        transcoder.register(CMyIntAsInt())

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
    dog_id = school.register_dog("Fido", MyInt(2))
    school.add_trick(dog_id, "roll over")
    school.add_trick(dog_id, "play dead")
    school.update_age(dog_id, MyInt(5))

    # Query application state.
    dog = school.get_dog(dog_id)
    assert dog["name"] == "Fido"
    assert dog["tricks"] == ("roll over", "play dead")
    assert dog["age"] == MyInt(5)

    # Select notifications.
    notifications = school.notification_log.select(start=1, limit=10)
    assert len(notifications) == 4
```

See the [library docs](https://eventsourcing.readthedocs.io/en/stable/topics/persistence.html#transcodings)
for more information about transcoding, but please note the `CTranscoder` uses a slightly
different API.


## Developers

After cloning the repository, you can set up a virtual environment and
install dependencies by running the following command in the root
folder.

    $ make install

After making changes, please run the tests.

    $ make test

Check the formatting of the code.

    $ make lint

You can automatically reformat the code by running the following command.

    $ make fmt

If the project dependencies change, you can update your packages by running
the following command.

    $ make update-packages

Please submit changes for review by making a pull request.
