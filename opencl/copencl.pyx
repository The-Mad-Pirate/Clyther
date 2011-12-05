'''

'''
import weakref
import struct
import ctypes
from opencl.type_formats import refrence, ctype_from_format, type_format, cdefn
from opencl.errors import OpenCLException

from libc.stdlib cimport malloc, free 
from libc.stdio cimport printf
from _cl cimport * 
from cpython cimport PyObject, Py_DECREF, Py_INCREF, PyBuffer_IsContiguous, PyBuffer_FillContiguousStrides
from cpython cimport Py_buffer, PyBUF_SIMPLE, PyBUF_STRIDES, PyBUF_ND, PyBUF_FORMAT, PyBUF_INDIRECT, PyBUF_WRITABLE
from kernel cimport KernelFromPyKernel, KernelAsPyKernel
from cl_mem cimport clMemFrom_pyMemoryObject


cdef extern from "Python.h":

    object PyByteArray_FromStringAndSize(char * , Py_ssize_t)
    object PyMemoryView_FromBuffer(Py_buffer * info)
    int PyObject_GetBuffer(object obj, Py_buffer * view, int flags)
    int PyObject_CheckBuffer(object obj)
    void PyBuffer_Release(Py_buffer * view)
    void PyEval_InitThreads()

MAGIC_NUMBER = 0xabc123

    
PyEval_InitThreads()


cpdef get_platforms():
    '''
    '''
    cdef cl_uint num_platforms
    cdef cl_platform_id plid
    
    ret = clGetPlatformIDs(0, NULL, & num_platforms)
    if ret != CL_SUCCESS:
        raise OpenCLException(ret)
    cdef cl_platform_id * cl_platform_ids = < cl_platform_id *> malloc(num_platforms * sizeof(cl_platform_id *))
    
    ret = clGetPlatformIDs(num_platforms, cl_platform_ids, NULL)
    
    if ret != CL_SUCCESS:
        free(cl_platform_ids)
        raise OpenCLException(ret)
    
    platforms = []
    for i in range(num_platforms):
        plat = Platform()
        plat.platform_id = cl_platform_ids[i]
        platforms.append(plat)
        
    free(cl_platform_ids)
    return platforms
    

cdef class Platform:

    cdef cl_platform_id platform_id
    
    def __cinit__(self):
        pass
    
    def __repr__(self):
        return '<opencl.Platform name=%r profile=%r>' % (self.name, self.profile,)

    
    cdef get_info(self, cl_platform_info info_type):
        cdef size_t size
        cdef cl_int err_code
        err_code = clGetPlatformInfo(self.platform_id,
                                   info_type, 0,
                                   NULL, & size)
        
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)
        
        cdef char * result = < char *> malloc(size * sizeof(char *))
        
        err_code = clGetPlatformInfo(self.platform_id,
                                   info_type, size,
                                   result, NULL)
        
        if err_code != CL_SUCCESS:
            free(result)
            raise OpenCLException(err_code)
        
        cdef bytes a_python_byte_string = result
        free(result)
        return a_python_byte_string

    property profile:
        def __get__(self):
            return self.get_info(CL_PLATFORM_PROFILE)

    property version:
        def __get__(self):
            return self.get_info(CL_PLATFORM_VERSION)

    property name:
        def __get__(self):
            return self.get_info(CL_PLATFORM_NAME)

    property vendor:
        def __get__(self):
            return self.get_info(CL_PLATFORM_VENDOR)

    property extensions:
        def __get__(self):
            return self.get_info(CL_PLATFORM_EXTENSIONS)

    def  devices(self, cl_device_type dtype=CL_DEVICE_TYPE_ALL):

        cdef cl_int err_code
           
        cdef cl_uint num_devices
        err_code = clGetDeviceIDs(self.platform_id, dtype, 0, NULL, & num_devices)
            
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)
        
        cdef cl_device_id * result = < cl_device_id *> malloc(num_devices * sizeof(cl_device_id *))
        
        err_code = clGetDeviceIDs(self.platform_id, dtype, num_devices, result, NULL)
        
        devices = []
        for i in range(num_devices):
            device = Device()
            device.device_id = result[i]
            devices.append(device)
            
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)
        
        return devices
        
cdef class Device:
    DEFAULT = CL_DEVICE_TYPE_DEFAULT
    ALL = CL_DEVICE_TYPE_ALL
    CPU = CL_DEVICE_TYPE_CPU
    GPU = CL_DEVICE_TYPE_GPU
    
    cdef cl_device_id device_id

    def __cinit__(self):
        pass
    
    def __repr__(self):
        return '<opencl.Device name=%r type=%r>' % (self.name, self.device_type,)
    
    def __hash__(Device self):
        
        cdef size_t hash_id = < size_t > self.device_id

        return int(hash_id)
    
    def __richcmp__(Device self, other, op):
        
        if not isinstance(other, Device):
            return NotImplemented
        
        if op == 2:
            return self.device_id == (< Device > other).device_id
        else:
            return NotImplemented
            
            
             
    property device_type:
        def __get__(self):
            cdef cl_int err_code
            cdef cl_device_type dtype
            
            
            err_code = clGetDeviceInfo(self.device_id, CL_DEVICE_TYPE, sizeof(cl_device_type), < void *>& dtype, NULL)
                
            if err_code != CL_SUCCESS:
                raise OpenCLException(err_code)
            
            return dtype

    property has_image_support:
        def __get__(self):
            cdef cl_int err_code
            cdef cl_bool result
            
            err_code = clGetDeviceInfo(self.device_id, CL_DEVICE_IMAGE_SUPPORT, sizeof(cl_bool), < void *>& result, NULL)
                
            if err_code != CL_SUCCESS:
                raise OpenCLException(err_code)
            
            return True if result else False
    

    property name:
        def __get__(self):
            cdef size_t size
            cdef cl_int err_code
            err_code = clGetDeviceInfo(self.device_id, CL_DEVICE_NAME, 0, NULL, & size)
            
            if err_code != CL_SUCCESS:
                raise OpenCLException(err_code)
            
            cdef char * result = < char *> malloc(size * sizeof(char *))
            
            err_code = clGetDeviceInfo(self.device_id, CL_DEVICE_NAME, size * sizeof(char *), < void *> result, NULL)

            if err_code != CL_SUCCESS:
                free(result)
                raise OpenCLException(err_code)
            
            cdef bytes a_python_byte_string = result
            free(result)
            return a_python_byte_string

    property native_kernel:

        def __get__(self):
            cdef size_t size
            cdef cl_int err_code
            cdef cl_device_exec_capabilities result
            
            err_code = clGetDeviceInfo(self.device_id, CL_DEVICE_EXECUTION_CAPABILITIES, sizeof(cl_device_exec_capabilities), & result, NULL)
            
            if err_code != CL_SUCCESS:
                raise OpenCLException(err_code)
            
            
            return True if result & CL_EXEC_NATIVE_KERNEL else False 


cdef class ContextProperties:

    cdef cl_platform_id platform_id
    cdef size_t _gl_context
    cdef size_t _gl_sharegroup
    
    def __cinit__(self):
        self.platform_id = NULL
        self.gl_context = 0
        self._gl_sharegroup = 0
        
    property platform:
        def __get__(self):
            if self.platform_id != NULL:
                return clPlatformAs_PyPlatform(self.platform_id)
            else:
                return None

        def __set__(self, Platform value):
            self.platform_id = clPlatformFromPyPlatform(value)

    property gl_context:
        def __get__(self):
            return self._gl_context

        def __set__(self, value):
            self._gl_context = value
            
    property gl_sharegroup:
        def __get__(self):
            return self._gl_sharegroup

        def __set__(self, value):
            self._gl_sharegroup = value
    
    @classmethod
    def get_current_opengl_context(cls):
        return < size_t > CGLGetCurrentContext()

    @classmethod
    def get_current_opengl_sharegroup(cls):
        return < size_t > CGLGetShareGroup(< void *> CGLGetCurrentContext())
        
    def as_dict(self):
        nprops = 0
        
        if self.platform_id != NULL:
            nprops += 1
        if self._gl_context != 0:
            nprops += 1
        if self._gl_context != 0:
            nprops += 1
            
        props = {}
           
        if self.platform_id != NULL:
             props[ < size_t > CL_CONTEXT_PLATFORM] = < size_t > self.platform_id
        if self._gl_sharegroup != 0:
             props[ < size_t > CL_CONTEXT_PROPERTY_USE_CGL_SHAREGROUP_APPLE] = < size_t > self._gl_sharegroup
        
        props[nprops * 2] = None
        
        return props
    
        
    cdef cl_context_properties * context_properties(self):
        
        nprops = 0
        cdef cl_context_properties * props = NULL
        
        if self.platform_id != NULL:
            nprops += 1
        if self._gl_context != 0:
            nprops += 1
        if self._gl_sharegroup != 0:
            nprops += 1
            
        if nprops > 0:
            props = < cl_context_properties *> malloc(sizeof(cl_context_properties) * (1 + 2 * nprops))
           
        cdef count = 0
        if self.platform_id != NULL:
             props[count] = CL_CONTEXT_PLATFORM
             count += 1
             props[count] = < cl_context_properties > self.platform_id
             count += 1

        if self._gl_context != 0:
             props[count] = < cl_context_properties > CL_CONTEXT_PROPERTY_USE_CGL_SHAREGROUP_APPLE
             count += 1
             props[count] = < cl_context_properties > self._gl_context
             count += 1
             
        if self._gl_sharegroup != 0:
             props[count] = < cl_context_properties > CL_CONTEXT_PROPERTY_USE_CGL_SHAREGROUP_APPLE
             count += 1
             props[count] = < cl_context_properties > self._gl_sharegroup
             count += 1
             
        props[count] = < cl_context_properties > 0
        
        return props
    
    def __repr__(self):
        return '<ContextProperties platform=%r gl_context=%r gl_sharegroup=%r>' % (self.platform, self.gl_context, self.gl_sharegroup)
    
_context_errors = {
                       CL_INVALID_PLATFORM : ('Properties is NULL and no platform could be selected or if ' 
                                              'platform value specified in properties is not a valid platform.'),
                   CL_INVALID_PROPERTY: ('Context property name in properties is not a supported ' 
                                         'property name, if the value specified for a supported property name is not valid, or if the ' 
                                         'same property name is specified more than once.'),
                   CL_INVALID_VALUE: 'pfn_notify is NULL but user_data is not NULL.',
                   CL_INVALID_DEVICE_TYPE :'device_type is not a valid value.',
                   CL_DEVICE_NOT_AVAILABLE : ('No devices that match device_type and property values' 
                                              'specified in properties are currently available.'),
                                               
                   CL_DEVICE_NOT_FOUND: ('No devices that match device_type and property values ' 
                                        'specified in properties were found.'),
                   CL_OUT_OF_RESOURCES: ('There is a failure to allocate resources required by the ' 
                                         'OpenCL implementation on the device.'),
                   CL_OUT_OF_HOST_MEMORY :('There is a failure to allocate resources required by the ' 
                                           'OpenCL implementation on the host'),
                   }
cdef class Context:
    cdef cl_context context_id
    
    def __cinit__(self):
        self.context_id = NULL
        
    def __init__(self, devices=(), device_type=CL_DEVICE_TYPE_DEFAULT, ContextProperties properties=None):
        
        cdef cl_context_properties * props = NULL
        
        if properties is not None:
            props = properties.context_properties()
        
        cdef cl_device_type dtype
        cdef cl_int err_code
        cdef cl_uint num_devices
        cdef cl_device_id * _devices = NULL

        if devices:
            num_devices = len(devices)
            _devices = < cl_device_id *> malloc(num_devices * sizeof(cl_device_id))
            for i in range(num_devices): 
                _devices[i] = (< Device > devices[i]).device_id
                 
            self.context_id = clCreateContext(props, num_devices, _devices, NULL, NULL, & err_code)
            
            if _devices != NULL:
                free(_devices)

            if err_code != CL_SUCCESS:
                raise OpenCLException(err_code, _context_errors)
        else:
            dtype = < cl_device_type > device_type
            self.context_id = clCreateContextFromType(props, dtype, NULL, NULL, & err_code)
    
            if err_code != CL_SUCCESS:
                raise OpenCLException(err_code, _context_errors)

    
    def __dealloc__(self):
        if self.context_id != NULL:
            clReleaseContext(self.context_id)
        self.context_id = NULL
        
    def __repr__(self):
        return '<opencl.Context>'
    
    def retain(self):
        clRetainContext(self.context_id)

    def release(self):
        clReleaseContext(self.context_id)
    
    property ref_count:
        def __get__(self):
            pass
        
    property devices:
        def __get__(self):
            
            cdef cl_int err_code
            cdef size_t num_devices
            cdef cl_device_id * _devices
            err_code = clGetContextInfo (self.context_id, CL_CONTEXT_DEVICES, 0, NULL, & num_devices)
    
            if err_code != CL_SUCCESS:
                raise OpenCLException(err_code)
    
            _devices = < cl_device_id *> malloc(num_devices * sizeof(cl_device_id))
    
            err_code = clGetContextInfo (self.context_id, CL_CONTEXT_DEVICES, num_devices, _devices, NULL)
    
            if err_code != CL_SUCCESS:
                free(_devices)
                raise OpenCLException(err_code)
            
            devices = []
            for i in range(num_devices): 
                device = Device()
                device.device_id = _devices[i]
                devices.append(device) 
                
            free(_devices)
            
            return devices

cdef struct UserData:
    int magic
    PyObject * function
    PyObject * args
    PyObject * kwargs
     
cdef void user_func(void * data) with gil:
    cdef UserData user_data = (< UserData *> data)[0]
    
    if user_data.magic != MAGIC_NUMBER:
        raise Exception("Enqueue native kernel can not be used at this time") 

    cdef object function = < object > user_data.function
    cdef object args = < object > user_data.args
    cdef object kwargs = < object > user_data.kwargs
    
    function(*args, **kwargs)
    
    Py_DECREF(< object > user_data.function)
    Py_DECREF(< object > user_data.args)
    Py_DECREF(< object > user_data.kwargs)
    
    return
    
_enqueue_copy_buffer_errors = {
                               

    CL_INVALID_COMMAND_QUEUE: 'if command_queue is not a valid command-queue.',

    CL_INVALID_CONTEXT: ('The context associated with command_queue, src_buffer and '
    'dst_buffer are not the same or if the context associated with command_queue and events ' 
    'in event_wait_list are not the same.'),
                               
    CL_INVALID_MEM_OBJECT: 'source and dest are not valid buffer objects.',
    
    CL_INVALID_VALUE : ('source, dest, size, src_offset / cb or dst_offset / cb '
                        'require accessing elements outside the src_buffer and dst_buffer buffer objects ' 
                        'respectively. '),
    CL_INVALID_EVENT_WAIT_LIST :('event_wait_list is NULL and ' 
                                 'num_events_in_wait_list > 0, or event_wait_list is not NULL and ' 
                                 'num_events_in_wait_list is 0, or if event objects in event_wait_list are not valid events.'),
                               }

nd_range_kernel_errors = {
    CL_INVALID_PROGRAM_EXECUTABLE : ('There is no successfully built program '
                                     'executable available for device associated with command_queue.'),
    CL_INVALID_COMMAND_QUEUE : 'command_queue is not a valid command-queue.',
    CL_INVALID_KERNEL :'kernel is not a valid kernel object',
    CL_INVALID_CONTEXT: ('Context associated with command_queue and kernel are not ' 
                         'the same or if the context associated with command_queue and events in event_wait_list '
                         'are not the same.'),
    CL_INVALID_KERNEL_ARGS : 'The kernel argument values have not been specified.',
    CL_INVALID_WORK_DIMENSION : 'work_dim is not a valid value',
    CL_INVALID_GLOBAL_WORK_SIZE : ('global_work_size is NULL, or if any of the ' 
                                   'values specified in global_work_size[0], ... ' 
                                   'global_work_size[work_dim - 1] are 0 or ' 
                                   'exceed the range given by the sizeof(size_t) for the device on which the kernel ' 
                                   'execution will be enqueued.'),
    CL_INVALID_GLOBAL_OFFSET : ('The value specified in global_work_size + the ' 
                                'corresponding values in global_work_offset for any dimensions is greater than the ' 
                                'sizeof(size t) for the device on which the kernel execution will be enqueued. '),
    CL_INVALID_WORK_GROUP_SIZE :('local_work_size is specified and number of workitems specified by global_work_size is not evenly divisible by size of work-group given ' 
                                 'by local_work_size or does not match the work-group size specified for kernel'),
    CL_INVALID_WORK_GROUP_SIZE : ('local_work_size is specified and the total number ' 
                                  'of work-items in the work-group computed as local_work_size[0] * ... ' 
                                  'local_work_size[work_dim - 1] is greater than the value specified by CL_DEVICE_MAX_WORK_GROUP_SIZE'),
    CL_INVALID_WORK_GROUP_SIZE : ('local_work_size is NULL and the ' 
                                  '__attribute__((reqd_work_group_size(X, Y, Z))) qualifier is used to ' 
                                  'declare the work-group size for kernel in the program source. '),
    CL_INVALID_WORK_ITEM_SIZE :('The number of work-items specified in any of ' 
                                'local_work_size[0], ... local_work_size[work_dim - 1]    is greater than the ' 
                                'corresponding values specified by CL_DEVICE_MAX_WORK_ITEM_SIZES[0], ...CL_DEVICE_MAX_WORK_ITEM_SIZES[work_dim - 1].'),
    CL_MISALIGNED_SUB_BUFFER_OFFSET : ('A sub-buffer object is specified as the value ' 
                                       'for an argument that is a buffer object and the offset specified when the sub-buffer object ' 
                                       'is created is not aligned to CL_DEVICE_MEM_BASE_ADDR_ALIGN value for device ' 
                                       'associated with queue.'),
    CL_INVALID_IMAGE_SIZE : ('An image object is specified as an argument value and the ' 
                             'image dimensions (image width, height, specified or compute row and/or slice pitch) are ' 
                             'not supported by device associated with queue.'),
    CL_OUT_OF_RESOURCES  : 'CL_OUT_OF_RESOURCES, There is a failure to queue the execution instance of kernel ',
    CL_MEM_OBJECT_ALLOCATION_FAILURE :('There is a failure to allocate memory for ' 
                                       'data store associated with image or buffer objects specified as arguments to kernel. '),
    CL_INVALID_EVENT_WAIT_LIST: ('event_wait_list is NULL and ' 
                                 'num_events_in_wait_list > 0, or event_wait_list is not NULL and ' 
                                 'num_events_in_wait_list is 0, or if event objects in event_wait_list are not valid events. '),
    CL_OUT_OF_HOST_MEMORY : ('There is a failure to allocate resources required by the' 
                             'OpenCL implementation on the host')
}

cdef class Queue:
    
    cdef cl_command_queue queue_id
    
    def __cinit__(self, Context context, Device device, out_of_order_exec_mode=False, profiling=False):
        
        cdef cl_command_queue_properties properties = 0
        
        properties |= CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE if out_of_order_exec_mode else 0
        properties |= CL_QUEUE_PROFILING_ENABLE if profiling else 0
            
        cdef cl_int err_code = CL_SUCCESS
       
        self.queue_id = clCreateCommandQueue(context.context_id, device.device_id, properties, & err_code)
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)

    property device:
        def __get__(self):
            cdef cl_int err_code
            cdef cl_device_id device_id
             
            err_code = clGetCommandQueueInfo (self.queue_id, CL_QUEUE_DEVICE, sizeof(cl_device_id), & device_id, NULL)
            
            if err_code != CL_SUCCESS:
                raise OpenCLException(err_code)
            
            return DeviceIDAsPyDevice(device_id) 

    property context:
        def __get__(self):
            cdef cl_int err_code
            cdef cl_context context_id
             
            err_code = clGetCommandQueueInfo (self.queue_id, CL_QUEUE_CONTEXT, sizeof(cl_context), & context_id, NULL)
            
            if err_code != CL_SUCCESS:
                raise OpenCLException(err_code)
            
            return ContextAsPyContext(context_id) 
        
    def barrier(self):
        cdef cl_int err_code
        cdef cl_command_queue queue_id = self.queue_id
         
        with nogil:
            err_code = clEnqueueBarrier(queue_id)

        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)
        
    def flush(self):
        cdef cl_int err_code
         
        err_code = clFlush(self.queue_id)

        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)

    def finish(self):
        
        cdef cl_int err_code
        cdef cl_command_queue queue_id = self.queue_id
        
        with nogil:
            err_code = clFinish(queue_id) 

        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)
        
    def marker(self):
        
        
        cdef Event event = Event()
        cdef cl_int err_code
         
        err_code = clEnqueueMarker(self.queue_id, & event.event_id)
         
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)
        
        return event
        
    def copy(self, source, dest):
        pass
    
    def wait(self, *events):
        
        if len(events) == 1:
            if isinstance(events[0], (list, tuple)):
                events = events[0]
            else:
                events = (events[0],)
        
        cdef cl_event * event_wait_list
        cdef cl_uint num_events_in_wait_list = _make_wait_list(events, & event_wait_list)
        cdef cl_uint err_code
        
        err_code = clEnqueueWaitForEvents(self.queue_id, num_events_in_wait_list, event_wait_list)

        free(event_wait_list)
        
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)
    
#    def enqueue_read_buffer(self, buffer, host_destination, size_t offset=0, size=None, blocking=False, events=None):
#        
#        cdef cl_int err_code
#        cdef Py_buffer view
#
#        cdef cl_bool blocking_read = 1 if blocking else 0
#        cdef void * ptr = NULL
#        cdef cl_uint num_events_in_wait_list = 0
#        cdef cl_event * event_wait_list = NULL
#        cdef Event event = Event()   
#        cdef size_t cb   
#        cdef cl_mem buffer_id = (< Buffer > buffer).buffer_id
#
#        if PyObject_GetBuffer(host_destination, & view, PyBUF_SIMPLE | PyBUF_ANY_CONTIGUOUS):
#            raise ValueError("argument 'host_buffer' must be a readable buffer object")
#        
#        if size is None:
#            cb = min(view.len, buffer.size)
#            
#        if view.len < size:
#            raise Exception("destination (host) buffer is too small")
#        elif buffer.size < size:
#            raise Exception("source (device) buffer is too small")
#        
#        ptr = view.buf
#        
#        if events:
#            num_events_in_wait_list = len(events)
#            event_wait_list = < cl_event *> malloc(num_events_in_wait_list * sizeof(cl_event))
#            
#            for i in range(num_events_in_wait_list):
#                tmp_event = < Event > events[i]
#                event_wait_list[i] = tmp_event.event_id
#            
#        err_code = clEnqueueReadBuffer (self.queue_id, buffer_id,
#                                        blocking_read, offset, cb, ptr,
#                                        num_events_in_wait_list, event_wait_list, & event.event_id)
#    
#        if event_wait_list != NULL:
#            free(event_wait_list)
#        
#        if err_code != CL_SUCCESS:
#            raise OpenCLException(err_code)
#
#        if not blocking:
#            return event
#        
#    def enqueue_map_buffer(self, buffer, blocking=False, size_t offset=0, size=None, events=None, read=True, write=True, format="B", itemsize=1):
#        
#        cdef void * host_buffer = NULL
#        cdef cl_mem _buffer
#        cdef cl_bool blocking_map = 1 if blocking else 0
#        cdef cl_map_flags map_flags = 0
#        cdef size_t cb = 0
#        cdef cl_uint num_events_in_wait_list = 0
#        cdef cl_event * event_wait_list = NULL
#        cdef Event event
#        cdef cl_int err_code
#        
#        if read:
#            map_flags |= CL_MAP_READ
#        if write:
#            map_flags |= CL_MAP_WRITE
#            
#        
#
#        _buffer = (< Buffer > buffer).buffer_id
#        
#        if size is None:
#            cb = buffer.size - offset
#        else:
#            cb = < size_t > size
#            
#            
##        cdef Py_buffer * view = < Py_buffer *> malloc(sizeof(Py_buffer)) 
##        
##        cdef char * _format = < char *> format
##        view.itemsize = itemsize
##        
##        if not view.itemsize:
##            raise Exception()
##        if (cb % view.itemsize) != 0:
##            raise Exception("size-offset must be a multiple of itemsize of format %r (%i)" % (format, view.itemsize))
#
#        if events:
#            num_events_in_wait_list = len(events)
#            event_wait_list = < cl_event *> malloc(num_events_in_wait_list * sizeof(cl_event))
#            
#            for i in range(num_events_in_wait_list):
#                tmp_event = < Event > events[i]
#                event_wait_list[i] = tmp_event.event_id
#                
#        
#        host_buffer = clEnqueueMapBuffer (self.queue_id, _buffer, blocking_map, map_flags,
#                                          offset, cb, num_events_in_wait_list, event_wait_list,
#                                          & event.event_id, & err_code)
##        print "clEnqueueMapBuffer"
#        
#        
#        if event_wait_list != NULL:
#            free(event_wait_list)
#        
#        if err_code != CL_SUCCESS:
#            raise OpenCLException(err_code)
#
#        if host_buffer == NULL:
#            raise Exception("host buffer is null")
#        
#        if write:
#            memview = < object > PyBuffer_FromReadWriteMemory(host_buffer, cb)
#        else:
#            memview = < object > PyBuffer_FromMemory(host_buffer, cb)
#            
##        view.buf = host_buffer
##        view.len = cb
##        view.readonly = 0 if write else 1
##        view.format = _format
##        view.ndim = 1
##        view.shape = < Py_ssize_t *> malloc(sizeof(Py_ssize_t))
##        view.shape[0] = cb / view.itemsize 
##        view.strides = < Py_ssize_t *> malloc(sizeof(Py_ssize_t))
##        view.strides[0] = 1
##        view.suboffsets = < Py_ssize_t *> malloc(sizeof(Py_ssize_t))
##        view.suboffsets[0] = 0
##         
##        view.internal = NULL 
##         
##        
#        
#        
#        if not blocking:
#            return (memview, event)
#        else:
#            return (memview, None)
#        
#    def enqueue_unmap(self, memobject, buffer, events=None,):
#
#        cdef void * mapped_ptr = NULL
#        cdef cl_mem memobj = NULL 
#        cdef cl_uint num_events_in_wait_list = 0
#        cdef cl_event * event_wait_list = NULL
#        cdef Event event = Event()
#        
#        cdef cl_int err_code
#        memobj = (< Buffer > memobject).buffer_id
#        cdef Py_ssize_t buffer_len
#        
#        PyObject_AsReadBuffer(< PyObject *> buffer, & mapped_ptr, & buffer_len)
#
#        if events:
#            num_events_in_wait_list = len(events)
#            event_wait_list = < cl_event *> malloc(num_events_in_wait_list * sizeof(cl_event))
#            
#            for i in range(num_events_in_wait_list):
#                tmp_event = < Event > events[i]
#                event_wait_list[i] = tmp_event.event_id
#                
#        err_code = clEnqueueUnmapMemObject(self.queue_id, memobj, mapped_ptr, num_events_in_wait_list,
#                                        event_wait_list, & event.event_id)
#        
#        if event_wait_list != NULL:
#            free(event_wait_list)
#        
#        if err_code != CL_SUCCESS:
#            raise OpenCLException(err_code)
#        
#        return event
    
    def enqueue_native_kernel(self, function, *args, **kwargs):
        
        cdef UserData user_data
        
        user_data.magic = MAGIC_NUMBER 
        
        user_data.function = < PyObject *> function
        
        user_data.args = < PyObject *> args
        user_data.kwargs = < PyObject *> kwargs
        
        Py_INCREF(< object > user_data.function)
        Py_INCREF(< object > user_data.args)
        Py_INCREF(< object > user_data.kwargs)
                    
        cdef cl_int err_code
        cdef Event event = Event()
        cdef cl_uint num_events_in_wait_list = 0
        cdef cl_event * event_wait_list = NULL
        cdef cl_uint  num_mem_objects = 0 
        cdef cl_mem * mem_list = NULL
        cdef void ** args_mem_loc = NULL

        cdef void * _args = < void *>& user_data
        cdef size_t cb_args = sizeof(UserData)
        
        err_code = clEnqueueNativeKernel(self.queue_id,
                                      & user_func,
                                      _args,
                                      cb_args,
                                      num_mem_objects,
                                      mem_list,
                                      args_mem_loc,
                                      num_events_in_wait_list,
                                      event_wait_list,
                                      & event.event_id) 
                            
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)
    
        return event
    
    
    def enqueue_nd_range_kernel(self, kernel, cl_uint  work_dim,
                                global_work_size, global_work_offset=None, local_work_size=None, wait_on=()):
        
        cdef cl_kernel kernel_id = KernelFromPyKernel(kernel)
        
        cdef Event event = Event()
        
        cdef size_t * gsize = < size_t *> malloc(sizeof(size_t) * work_dim)
        cdef size_t * goffset = NULL
        cdef size_t * lsize = NULL
        if global_work_offset:
            goffset = < size_t *> malloc(sizeof(size_t) * work_dim)
        if local_work_size:
            lsize = < size_t *> malloc(sizeof(size_t) * work_dim)
         
        for i in range(work_dim):
            gsize[i] = < size_t > global_work_size[i]
            if goffset != NULL: goffset[i] = < size_t > global_work_offset[i]
            if lsize != NULL: lsize[i] = < size_t > local_work_size[i]
            
        cdef cl_event * event_wait_list
        cdef cl_uint num_events_in_wait_list = _make_wait_list(wait_on, & event_wait_list)
        cdef cl_int err_code

        err_code = clEnqueueNDRangeKernel(self.queue_id, kernel_id,
                                          work_dim, goffset, gsize, lsize,
                                          num_events_in_wait_list, event_wait_list, & event.event_id)
        
        if gsize != NULL: free(gsize)
        if goffset != NULL: free(goffset)
        if lsize != NULL: free(lsize)

        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code, nd_range_kernel_errors)
        
        return event
    
    def enqueue_copy_buffer(self, source, dest, size_t src_offset=0, size_t dst_offset=0, size_t size=0, wait_on=()):
        
        cdef cl_int err_code
        cdef Event event = Event()
        cdef cl_event * event_wait_list
        cdef cl_uint num_events_in_wait_list = _make_wait_list(wait_on, & event_wait_list)
        
        cdef cl_mem src_buffer = clMemFrom_pyMemoryObject(source)
        cdef cl_mem dst_buffer = clMemFrom_pyMemoryObject(dest)
        
        err_code = clEnqueueCopyBuffer(self.queue_id, src_buffer, dst_buffer, src_offset, dst_offset, size,
                                       num_events_in_wait_list, event_wait_list, & event.event_id)
        
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code, _enqueue_copy_buffer_errors)
    
        return event

    def enqueue_read_buffer(self, source, dest, size_t src_offset=0, size_t size=0, wait_on=(), cl_bool blocking_read=0):
        
        cdef cl_int err_code
        cdef Event event = Event()
        cdef cl_event * event_wait_list
        cdef cl_uint num_events_in_wait_list = _make_wait_list(wait_on, & event_wait_list)
        
        cdef cl_mem src_buffer = clMemFrom_pyMemoryObject(source)
        
        cdef int flags = PyBUF_SIMPLE
        
        if not PyObject_CheckBuffer(dest):
            raise Exception("dest argument of enqueue_read_buffer is required to be a new style buffer object (got %r)" % dest)

        cdef Py_buffer dst_buffer
        
        if PyObject_GetBuffer(dest, & dst_buffer, flags) < 0:
            raise Exception("dest argument of enqueue_read_buffer is required to be a new style buffer object")
        
        if dst_buffer.len < size:
            raise Exception("dest buffer must be at least `size` bytes")
        
        if not PyBuffer_IsContiguous(& dst_buffer, 'A'):
            raise Exception("dest buffer must be contiguous")
        
        err_code = clEnqueueReadBuffer(self.queue_id, src_buffer, blocking_read, src_offset, size, dst_buffer.buf,
                                       num_events_in_wait_list, event_wait_list, & event.event_id)
        
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code, _enqueue_copy_buffer_errors)
    
        return event
    
    def enqueue_write_buffer(self, source, dest, size_t src_offset=0, size_t size=0, wait_on=(), cl_bool blocking_read=0):
        
        cdef cl_int err_code
        cdef Event event = Event()
        cdef cl_event * event_wait_list
        cdef cl_uint num_events_in_wait_list = _make_wait_list(wait_on, & event_wait_list)
        
        cdef cl_mem src_buffer = clMemFrom_pyMemoryObject(source)
        
        cdef int flags = PyBUF_SIMPLE | PyBUF_WRITABLE
        
        if not PyObject_CheckBuffer(dest):
            raise Exception("dest argument of enqueue_read_buffer is required to be a new style buffer object (got %r)" % dest)

        cdef Py_buffer dst_buffer
        
        if PyObject_GetBuffer(dest, & dst_buffer, flags) < 0:
            raise Exception("dest argument of enqueue_read_buffer is required to be a new style buffer object")
        
        if dst_buffer.len < size:
            raise Exception("dest buffer must be at least `size` bytes")
        
        if not PyBuffer_IsContiguous(& dst_buffer, 'A'):
            raise Exception("dest buffer must be contiguous")

        if dst_buffer.readonly:
            raise Exception("host buffer must have write access")
        
        err_code = clEnqueueWriteBuffer(self.queue_id, src_buffer, blocking_read, src_offset, size, dst_buffer.buf,
                                       num_events_in_wait_list, event_wait_list, & event.event_id)
        
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code, _enqueue_copy_buffer_errors)
    
        return event


    def enqueue_copy_buffer_rect(self, source, dest, region, src_origin=(0, 0, 0), dst_origin=(0, 0, 0),
                                 size_t src_row_pitch=0, size_t src_slice_pitch=0,
                                 size_t dst_row_pitch=0, size_t dst_slice_pitch=0, wait_on=()):
        
        cdef cl_int err_code
        cdef Event event = Event()
        cdef cl_event * event_wait_list
        cdef cl_uint num_events_in_wait_list = _make_wait_list(wait_on, & event_wait_list)
        
        cdef cl_mem src_buffer = clMemFrom_pyMemoryObject(source)
        cdef cl_mem dst_buffer = clMemFrom_pyMemoryObject(dest)
        
        cdef size_t _src_origin[3]
        _src_origin[:] = [0, 0, 0]
        cdef  size_t _dst_origin[3]
        _dst_origin[:] = [0, 0, 0]
        cdef size_t _region[3]
        _region[:] = [1, 1, 1]
        
        for i, origin in enumerate(src_origin):
            _src_origin[i] = origin

        for i, origin in enumerate(dst_origin):
            _dst_origin[i] = origin

        for i, size in enumerate(region):
            _region[i] = size
        
        err_code = clEnqueueCopyBufferRect(self.queue_id, src_buffer, dst_buffer,
                                           _src_origin, _dst_origin, _region,
                                           src_row_pitch, src_slice_pitch,
                                           dst_row_pitch, dst_slice_pitch,
                                           num_events_in_wait_list, event_wait_list, & event.event_id)
                
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code, _enqueue_copy_buffer_errors)
    
        return event

cdef cl_uint _make_wait_list(wait_on, cl_event ** event_wait_list_ptr):
    if not wait_on:
        event_wait_list_ptr[0] = NULL
        return 0
    
    cdef cl_uint num_events = len(wait_on)
    cdef Event event
    cdef cl_event * event_wait_list = < cl_event *> malloc(sizeof(cl_event) * num_events)
    
    for i, pyevent in enumerate(wait_on):
        event = < Event > pyevent
        event_wait_list[i] = event.event_id
        
    event_wait_list_ptr[0] = event_wait_list
    return num_events
    
cdef void pfn_event_notify(cl_event event, cl_int event_command_exec_status, void * data) with gil:
    
    cdef object user_data = (< object > data)
    
    pyevent = cl_eventAs_PyEvent(event)
    
    try:
        user_data(pyevent, event_command_exec_status)
    except:
        Py_DECREF(< object > user_data)
        raise
    else:
        Py_DECREF(< object > user_data)
    

cdef class Event:

    QUEUED = CL_QUEUED
    SUBMITTED = CL_SUBMITTED
    RUNNING = CL_RUNNING
    COMPLETE = CL_COMPLETE
    
    STATUS_DICT = { CL_QUEUED: 'queued', CL_SUBMITTED:'submitted', CL_RUNNING: 'running', CL_COMPLETE:'complete'}
    
    cdef cl_event event_id
    
    def __cinit__(self):
        self.event_id = NULL

    def __dealloc__(self):
        if self.event_id != NULL:
            clReleaseEvent(self.event_id)
        self.event_id = NULL
        
    def __repr__(self):
        status = self.status
        return '<%s status=%r:%r>' % (self.__class__.__name__, status, self.STATUS_DICT[status])
    
    def wait(self):
        
        cdef cl_int err_code
        
        with nogil:
            err_code = clWaitForEvents(1, & self.event_id)
    
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)
        
    property status:
        def __get__(self):
            cdef cl_int err_code
            cdef cl_int status

            err_code = clGetEventInfo(self.event_id, CL_EVENT_COMMAND_EXECUTION_STATUS, sizeof(cl_int), & status, NULL)

            if err_code != CL_SUCCESS:
                raise OpenCLException(err_code)
            
            return status
        
    def add_callback(self, callback):
        
        cdef cl_int err_code

        Py_INCREF(callback)
        err_code = clSetEventCallback(self.event_id, CL_COMPLETE, < void *> & pfn_event_notify, < void *> callback) 
        
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)
        
        
cdef class UserEvent(Event):

    def __cinit__(self, Context context):
        
        cdef cl_int err_code

        self.event_id = clCreateUserEvent(context.context_id, & err_code)

        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)
        
    def complete(self):
        
        cdef cl_int err_code
        
        err_code = clSetUserEventStatus(self.event_id, CL_COMPLETE)
        
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)
        

clCreateKernel_errors = {
                         
                         
                         }
cdef class Program:
    cdef cl_program program_id
    
    def __cinit__(self):
        self.program_id = NULL
    
    def __dealloc__(self):
        if self.program_id != NULL:
            clReleaseProgram(self.program_id)
        self.program_id = NULL
        
    def __init__(self, Context context, source=None):
        
        cdef char * strings
        cdef cl_int err_code
        if source is not None:
            
            strings = source
            self.program_id = clCreateProgramWithSource(context.context_id, 1, & strings, NULL, & err_code)
            
    def build(self, devices=None, options=''):
        
        cdef cl_int err_code
        cdef char * _options = options
        cdef cl_uint num_devices = 0
        cdef cl_device_id * device_list = NULL
        
        err_code = clBuildProgram(self.program_id, num_devices, device_list, _options, NULL, NULL)
        
        if err_code != CL_SUCCESS:
            raise OpenCLException(err_code)

        return self
    
    property num_devices:
        def __get__(self):
            
            cdef cl_int err_code
            cdef cl_uint value
            err_code = clGetProgramInfo(self.program_id, CL_PROGRAM_NUM_DEVICES, sizeof(value), & value, NULL)

            if err_code != CL_SUCCESS:
                raise OpenCLException(err_code)
            
            return value
        

    property logs:
        def __get__(self):
            
            logs = []
            cdef size_t log_len
            cdef char * logstr
            cdef cl_int err_code
            cdef cl_device_id device_id
            
            for device in self.devices:
                
                device_id = (< Device > device).device_id

                err_code = clGetProgramBuildInfo (self.program_id, device_id, CL_PROGRAM_BUILD_LOG, 0, NULL, & log_len)
                
                if err_code != CL_SUCCESS: raise OpenCLException(err_code)
                
                if log_len == 0:
                    logs.append('')
                    continue
                
                logstr = < char *> malloc(log_len + 1)
                err_code = clGetProgramBuildInfo (self.program_id, device_id, CL_PROGRAM_BUILD_LOG, log_len, logstr, NULL)
                 
                if err_code != CL_SUCCESS: 
                    free(logstr)
                    raise OpenCLException(err_code)
                
                logstr[log_len] = 0
                logs.append(logstr)
                
            return logs
                
        
    property context:
        def __get__(self):
            
            cdef cl_int err_code
            cdef Context context = Context()
            
            err_code = clGetProgramInfo (self.program_id, CL_PROGRAM_CONTEXT, sizeof(cl_context), & context.context_id, NULL)
              
            if err_code != CL_SUCCESS:
                raise OpenCLException(err_code)
            
            return context
        
    def kernel(self, name):
        
        cdef cl_int err_code
        cdef cl_kernel kernel_id
        cdef char * kernel_name = name
        
        kernel_id = clCreateKernel(self.program_id, kernel_name, & err_code)
    
        if err_code != CL_SUCCESS:
            if err_code == CL_INVALID_KERNEL_NAME:
                raise KeyError('kernel %s not found in program' % name)
            raise OpenCLException(err_code, clCreateKernel_errors)
        
        return KernelAsPyKernel(kernel_id)

    property devices:
        def __get__(self):
            
            cdef cl_int err_code
            cdef cl_device_id * device_list
                        
            cdef cl_uint num_devices = self.num_devices
            
            device_list = < cl_device_id *> malloc(sizeof(cl_device_id) * num_devices)
            err_code = clGetProgramInfo (self.program_id, CL_PROGRAM_DEVICES, sizeof(cl_device_id) * num_devices, device_list, NULL)
            
            if err_code != CL_SUCCESS:
                free(device_list)
                raise OpenCLException(err_code)
            
            
            devices = []
            
            for i in range(num_devices):
                devices.append(DeviceIDAsPyDevice(device_list[i]))
                
            free(device_list)
            
            return devices
        

## API FUNCTIONS #### #### #### #### #### #### #### #### #### #### ####
## ############# #### #### #### #### #### #### #### #### #### #### ####
#===============================================================================
# 
#===============================================================================

cdef api cl_platform_id clPlatformFromPyPlatform(object py_platform):
    cdef Platform platform = < Platform > py_platform
    return platform.platform_id

cdef api object clPlatformAs_PyPlatform(cl_platform_id platform_id):
    cdef Platform platform = < Platform > Platform.__new__(Platform)
    platform.platform_id = platform_id
    return platform

cdef api cl_context ContextFromPyContext(object pycontext):
    cdef Context context = < Context > pycontext
    return context.context_id

cdef api object ContextAsPyContext(cl_context context):
    ctx = < Context > Context.__new__(Context)
    clRetainContext(context)
    ctx.context_id = context
    return ctx
#===============================================================================
# 
#===============================================================================

cdef api cl_device_id DeviceIDFromPyDevice(object py_device):
    cdef Device device = < Device > py_device
    return device.device_id

cdef api object DeviceIDAsPyDevice(cl_device_id device_id):
    cdef Device device = < Device > Device.__new__(Device)
    device.device_id = device_id
    return device



#===============================================================================
# 
#===============================================================================
cdef api object cl_eventAs_PyEvent(cl_event event_id):
    cdef Event event = < Event > Event.__new__(Event)
    clRetainEvent(event_id)
    event.event_id = event_id
    return event

## ############# #### #### #### #### #### #### #### #### #### #### ####
