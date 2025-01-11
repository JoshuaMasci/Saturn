#pragma once
#include <Jolt/Jolt.h>

template <class T>
struct JoltAllocator {
	typedef T value_type;
	JoltAllocator() noexcept {}

	// A converting copy constructor:
	template <class U>
	JoltAllocator(const JoltAllocator<U> &) {}
	template <class U>
	bool operator==(const JoltAllocator<U> &) const {
		return true;
	}
	template <class U>
	bool operator!=(const JoltAllocator<U> &) const {
		return false;
	}

	T *allocate(const size_t n) const { return (T *)JPH::Allocate(n); }
	void deallocate(T *const p, size_t) const noexcept { JPH::Free((void *)p); }
};
