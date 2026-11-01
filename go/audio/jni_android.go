//go:build android

package audio

import (
	"errors"
	"fmt"
	"runtime"
	"sync"
	"time"
	"unsafe"

	"github.com/ebitengine/purego"
)

type jvalue struct{ v uint64 }

var jniState struct {
	mu   sync.Mutex
	jvm  uintptr
	view uintptr
}

func jniFn(itf uintptr, idx int) uintptr {
	return *(*uintptr)(unsafe.Add(unsafe.Pointer(itf), idx*8))
}

func jniAttached() (env uintptr, release func(), err error) {
	runtime.LockOSThread()
	unlock := func() { runtime.UnlockOSThread() }
	jvm := jniState.jvm
	if jvm == 0 {
		unlock()
		return 0, nil, errors.New("audio: JavaVM not available")
	}
	var envp uintptr
	if r, _, _ := purego.SyscallN(jniFn(jvm, jvmGetEnv), jvm,
		uintptr(unsafe.Pointer(&envp)), jniVersion16); r == 0 && envp != 0 {
		return envp, unlock, nil
	}
	if r, _, _ := purego.SyscallN(jniFn(jvm, jvmAttachCurrentThread), jvm,
		uintptr(unsafe.Pointer(&envp)), 0); r != 0 {
		unlock()
		return 0, nil, fmt.Errorf("audio: JNI AttachCurrentThread failed (%d)", r)
	}
	return envp, func() {
		purego.SyscallN(jniFn(jvm, jvmDetachCurrentThread), jvm)
		unlock()
	}, nil
}

func jniSanity(env uintptr) error {
	ver := jniCall(env, jniEnvGetVersion)
	if ver>>16 != 1 || ver&0xFFFF == 0 {
		return fmt.Errorf("audio: JNI GetVersion returned 0x%X — ABI mismatch", ver)
	}
	return nil
}

func jniCall(env uintptr, idx int, args ...uintptr) uintptr {
	fn := jniFn(env, idx)
	full := make([]uintptr, 0, len(args)+1)
	full = append(full, env)
	full = append(full, args...)
	r1, _, _ := purego.SyscallN(fn, full...)
	return r1
}

func cstr(s string) (unsafe.Pointer, []byte) {
	b := make([]byte, len(s)+1)
	copy(b, s)
	return unsafe.Pointer(&b[0]), b
}

func jniExceptionCheck(env uintptr) bool {
	return jniCall(env, jniEnvExceptionCheck) != 0
}

func jniExceptionClear(env uintptr) {
	jniCall(env, jniEnvExceptionClear)
}

func jniDeleteLocalRef(env, ref uintptr) {
	if ref != 0 {
		jniCall(env, jniEnvDeleteLocalRef, ref)
	}
}

func jniGetObjectClass(env, obj uintptr) uintptr {
	if obj == 0 {
		return 0
	}
	return jniCall(env, jniEnvGetObjectClass, obj)
}

func jniGetMethodID(env, cls uintptr, name, sig string) uintptr {
	if cls == 0 {
		return 0
	}
	np, nKeep := cstr(name)
	sp, sKeep := cstr(sig)
	mid := jniCall(env, jniEnvGetMethodID, cls, uintptr(np), uintptr(sp))
	runtime.KeepAlive(nKeep)
	runtime.KeepAlive(sKeep)
	if mid == 0 {
		jniExceptionClear(env)
	}
	return mid
}

func jniFindClass(env uintptr, name string) uintptr {
	np, keep := cstr(name)
	cls := jniCall(env, jniEnvFindClass, uintptr(np))
	runtime.KeepAlive(keep)
	if cls == 0 {
		jniExceptionClear(env)
	}
	return cls
}

func jniNewStringUTF(env uintptr, s string) uintptr {
	np, keep := cstr(s)
	jstr := jniCall(env, jniEnvNewStringUTF, uintptr(np))
	runtime.KeepAlive(keep)
	if jstr == 0 {
		jniExceptionClear(env)
	}
	return jstr
}

func jniCallObjectMethodA(env, obj, mid uintptr, args []jvalue) uintptr {
	if obj == 0 || mid == 0 {
		return 0
	}
	var argp unsafe.Pointer
	if len(args) > 0 {
		argp = unsafe.Pointer(&args[0])
	}
	res := jniCall(env, jniEnvCallObjectMethodA, obj, mid, uintptr(argp))
	runtime.KeepAlive(args)
	if res == 0 && jniExceptionCheck(env) {
		jniExceptionClear(env)
	}
	return res
}

func jniCallIntMethodA(env, obj, mid uintptr, args []jvalue) int32 {
	if obj == 0 || mid == 0 {
		return -1
	}
	res := jniCall(env, jniEnvCallIntMethodA, obj, mid, uintptr(unsafe.Pointer(&args[0])))
	runtime.KeepAlive(args)
	if res == 0 && jniExceptionCheck(env) {
		jniExceptionClear(env)
		return -1
	}
	return int32(res)
}

func jniCallVoidMethodA(env, obj, mid uintptr, args []jvalue) {
	if obj == 0 || mid == 0 {
		return
	}
	jniCall(env, jniEnvCallVoidMethodA, obj, mid, uintptr(unsafe.Pointer(&args[0])))
	runtime.KeepAlive(args)
	if jniExceptionCheck(env) {
		jniExceptionClear(env)
	}
}

func jniNewObjectArray(env uintptr, n int, cls uintptr, init uintptr) uintptr {
	arr := jniCall(env, jniEnvNewObjectArray, uintptr(n), cls, init)
	if arr == 0 {
		jniExceptionClear(env)
	}
	return arr
}

func jniSetObjectArrayElement(env, arr uintptr, idx int, val uintptr) {
	jniCall(env, jniEnvSetObjectArrayElement, arr, uintptr(idx), val)
	if jniExceptionCheck(env) {
		jniExceptionClear(env)
	}
}

func jniViewActivity(env uintptr) uintptr {
	view := jniState.view
	if view == 0 {
		return 0
	}
	vcls := jniGetObjectClass(env, view)
	mid := jniGetMethodID(env, vcls, "getContext", "()Landroid/content/Context;")
	if mid == 0 {
		return 0
	}
	ctx := jniCallObjectMethodA(env, view, mid, nil)
	if ctx == 0 {
		return 0
	}
	actCls := jniFindClass(env, "android/app/Activity")
	obj := ctx
	for i := 0; i < 4 && obj != 0; i++ {
		if actCls != 0 && jniCall(env, jniEnvIsInstanceOf, obj, actCls) != 0 {
			return obj
		}
		objCls := jniGetObjectClass(env, obj)
		getBase := jniGetMethodID(env, objCls, "getBaseContext", "()Landroid/content/Context;")
		if getBase == 0 {
			break
		}
		next := jniCallObjectMethodA(env, obj, getBase, nil)
		if next == 0 {
			break
		}
		obj = next
	}
	return 0
}

func jniCheckSelfPermission(env, ctx uintptr, perm string) bool {
	if ctx == 0 {
		return false
	}
	cls := jniGetObjectClass(env, ctx)
	mid := jniGetMethodID(env, cls, "checkSelfPermission", "(Ljava/lang/String;)I")
	if mid == 0 {
		return false
	}
	jstr := jniNewStringUTF(env, perm)
	if jstr == 0 {
		return false
	}
	defer jniDeleteLocalRef(env, jstr)
	res := jniCallIntMethodA(env, ctx, mid, []jvalue{{uint64(jstr)}})
	return res == 0
}

func jniRequestPermissions(env, activity uintptr, perms []string) {
	if activity == 0 {
		return
	}
	cls := jniGetObjectClass(env, activity)
	mid := jniGetMethodID(env, cls, "requestPermissions", "([Ljava/lang/String;I)V")
	if mid == 0 {
		return
	}
	strCls := jniFindClass(env, "java/lang/String")
	if strCls == 0 {
		return
	}
	arr := jniNewObjectArray(env, len(perms), strCls, 0)
	if arr == 0 {
		return
	}
	for i, p := range perms {
		jstr := jniNewStringUTF(env, p)
		jniSetObjectArrayElement(env, arr, i, jstr)
		jniDeleteLocalRef(env, jstr)
	}
	jniCallVoidMethodA(env, activity, mid, []jvalue{{uint64(arr)}, {1}})
	jniDeleteLocalRef(env, arr)
}

func micPermissionGranted() bool {
	env, release, err := jniAttached()
	if err != nil {
		return false
	}
	defer release()
	if jniSanity(env) != nil {
		return false
	}
	ctx := jniViewActivity(env)
	if ctx == 0 {
		return false
	}
	return jniCheckSelfPermission(env, ctx, "android.permission.RECORD_AUDIO")
}

const micPermissionTimeout = 10 * time.Second

func ensureMicPermission() error {
	if micPermissionGranted() {
		return nil
	}
	if jniState.view == 0 {
		return errors.New("audio: microphone permission required — window not ready yet, retry")
	}
	env, release, err := jniAttached()
	if err != nil {
		return err
	}
	if serr := jniSanity(env); serr != nil {
		release()
		return serr
	}
	activity := jniViewActivity(env)
	if activity == 0 {
		release()
		return errors.New("audio: microphone permission required — activity not found")
	}
	jniRequestPermissions(env, activity, []string{"android.permission.RECORD_AUDIO"})
	release()

	deadline := time.Now().Add(micPermissionTimeout)
	for time.Now().Before(deadline) {
		time.Sleep(250 * time.Millisecond)
		if micPermissionGranted() {
			return nil
		}
	}
	return errors.New("audio: microphone permission not granted")
}
