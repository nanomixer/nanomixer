import itertools
from functools import partial


def flattened(iterable):
    iterable = iter(iterable)
    while True:
        item = next(iterable)
        try:
            iterable = itertools.chain(iter(item), iterable)
        except TypeError:
            yield item


# From http://docs.python.org/2/library/itertools.html
def roundrobin(*iterables):
    "roundrobin('ABC', 'D', 'EF') --> A D E B F C"
    # Recipe credited to George Sakkis
    pending = len(iterables)
    iterables = (iter(it) for it in iterables)
    nexts = itertools.cycle(partial(next, it) for it in iterables)
    while pending:
        try:
            for next_thunk in nexts:
                yield next_thunk()
        except StopIteration:
            pending -= 1
            nexts = itertools.cycle(itertools.islice(nexts, pending))
