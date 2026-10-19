/* Skill Pre-Allocation native module: the DLL's entry point, and the two C runtime functions the module
 * takes from Windows' own C runtime (ucrtbase.dll) by hand.
 *
 * The DLL is linked without MinGW-w64's C runtime (generator/build_native.py: -nostdlib): its start-up
 * code brings things the module doesn't use (thread-local storage and atexit support, and a fixer for
 * references into other DLLs' data, which imports VirtualQuery and VirtualProtect). So the DLL imports only
 * the functions the module itself calls: Windows' file and folder functions (kernel32) and, from
 * ucrtbase.dll, malloc/free/qsort and the string functions. The module needs no start-up work:
 * the entry point does nothing. */
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdarg.h>
#include <stddef.h>

BOOL WINAPI spa_dll_entry(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
	(void)instance;
	(void)reason;
	(void)reserved;
	return TRUE;
}

/* (the linker asks for it in any DLL; the module has no thread-local data) */
ULONG _tls_index = 0;

/* snprintf and vsnprintf, as the C runtime's own headers make them: its formatter, with C99's behaviour
 * (the length the whole text needs is returned, the buffer always ends in a zero) */
__declspec(dllimport) int __cdecl __stdio_common_vsprintf(unsigned __int64 options, char *buffer, size_t count,
	const char *format, void *locale, va_list args);
#define SPA_C99_SNPRINTF 2ULL           /* _CRT_INTERNAL_PRINTF_STANDARD_SNPRINTF_BEHAVIOR */

int __cdecl vsnprintf(char *buffer, size_t count, const char *format, va_list args)
{
	int n = __stdio_common_vsprintf(SPA_C99_SNPRINTF, buffer, count, format, NULL, args);
	return n < 0 ? -1 : n;
}

int __cdecl snprintf(char *buffer, size_t count, const char *format, ...)
{
	va_list args;
	int n;

	va_start(args, format);
	n = vsnprintf(buffer, count, format, args);
	va_end(args);
	return n;
}
#else
typedef int spa_dllmain_unused;         /* (ISO C wants something in a file) */
#endif
