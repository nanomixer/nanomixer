import itertools


def flattened(iterable):
    iterable = iter(iterable)
    while True:
        item = iterable.next()
        try:
            iterable = itertools.chain(iter(item), iterable)
        except TypeError:
            yield item


# From http://docs.python.org/2/library/itertools.html
def roundrobin(*iterables):
    "roundrobin('ABC', 'D', 'EF') --> A D E B F C"
    # Recipe credited to George Sakkis
    pending = len(iterables)
    nexts = itertools.cycle(iter(it).next for it in iterables)
    while pending:
        try:
            for next in nexts:
                yield next()
        except StopIteration:
            pending -= 1
            nexts = itertools.cycle(itertools.islice(nexts, pending))
