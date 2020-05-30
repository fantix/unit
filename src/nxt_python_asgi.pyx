# cython: language_level=3
import asyncio
import sys
import traceback
from asyncio.events import AbstractEventLoop

from libc.stdint cimport uint32_t
from libc.string cimport memset


cdef extern from "nxt_unit_typedefs.h":
    ctypedef struct nxt_unit_request_info_t:
        pass

cdef extern from "nxt_unit.h":
    cdef enum:
        NXT_UNIT_OK
        NXT_UNIT_ERROR

    cdef void nxt_unit_request_done(nxt_unit_request_info_t *req, int rc)

cdef extern from "nxt_main.h":
    ctypedef struct nxt_event_engine_t:
        pass

    ctypedef struct nxt_thread_t:
        nxt_event_engine_t       *engine;

    ctypedef struct nxt_task_t:
        nxt_thread_t  *thread;

    ctypedef void (*nxt_work_handler_t)(nxt_task_t *task, void *obj, void *data)

cdef extern from "nxt_time.h":
    ctypedef uint32_t nxt_msec_t

cdef extern from "nxt_timer.h":
    ctypedef struct nxt_timer_t:
        nxt_work_handler_t handler

    void nxt_timer_add(nxt_event_engine_t *engine, nxt_timer_t *timer,
                       nxt_msec_t timeout);


cdef class Handle:
    cdef:
        object _callback
        object _args
        nxt_timer_t timer

    def __init__(self, callback, args):
        self._callback = callback
        self._args = args

    def __cinit__(self):
        memset(&self.timer, 0, sizeof(nxt_timer_t))
        self.timer.handler = timer_callback

    cdef run(self):
        self._callback(*self._args)

    cdef activate(self, nxt_event_engine_t *engine, nxt_msec_t delay):
        print('activate')
        nxt_timer_add(engine, &self.timer, delay)
        print('activate done')

    cdef Py_ssize_t timer_offset(self):
        return <Py_ssize_t>&self.timer - <Py_ssize_t><void*>self

cdef Py_ssize_t handle_timer_offset = Handle(None, None).timer_offset()

cdef void timer_callback(nxt_task_t *task, void *obj, void *data) with gil:
    print('timer_callback')
    cdef Handle handle = <Handle>(<void*>obj - handle_timer_offset)
    print(handle._callback, handle._args)
    handle.run()


cdef class NginxUnitEventLoop:
    cdef nxt_event_engine_t *engine

    def call_later(self, delay, callback, *args):
        rv = Handle(callback, args)
        rv.activate(self.engine, delay * 1000)
        return rv

cdef NginxUnitEventLoop loop


class NginxUnitEventLoopPolicy(asyncio.AbstractEventLoopPolicy):
    def get_event_loop(self) -> AbstractEventLoop:
        return loop


cdef public int nxt_python_asgi_install_loop(nxt_event_engine_t *engine):
    global loop
    loop = NginxUnitEventLoop()
    loop.engine = engine
    asyncio.set_event_loop_policy(NginxUnitEventLoopPolicy())
    return NXT_UNIT_OK

cdef public void nxt_python_asgi_request_handler(nxt_unit_request_info_t *req) with gil:
    try:
        def request():
            nxt_unit_request_done(req, NXT_UNIT_OK)
        loop.call_later(1, request)
    except BaseException:
        traceback.print_exc()
        sys.stderr.flush()
        nxt_unit_request_done(req, NXT_UNIT_ERROR)
