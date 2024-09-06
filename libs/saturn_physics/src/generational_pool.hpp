#include <cassert>
#include <optional>
#include <stdint.h>
#include <vector>

#include "jolt_allocator.hpp"

template <typename T>
class GenerationalPool {
public:
  struct Handle {
	uint32_t id;
	uint32_t generation;

	bool operator==(const Handle &other) const {
	  return id == other.id && generation == other.generation;
	}

	uint64_t to_u64() const {
	  return (static_cast<uint64_t>(generation) << 32) | id;
	}

	static Handle from_u64(uint64_t value)

	{
	  uint32_t id = static_cast<uint32_t>(value & 0xFFFFFFFF);
	  uint32_t generation = static_cast<uint32_t>((value >> 32) & 0xFFFFFFFF);
	  return Handle{id, generation};
	}
  };

private:
  struct Entry {
	std::optional<T> data;
	uint32_t generation;
  };

  std::vector<Entry, JoltAllocator<Entry>> entries;
  std::vector<uint32_t, JoltAllocator<uint32_t>> freeList;

public:
  GenerationalPool() = default;

  Handle add(const T &data) {
	uint32_t id;
	uint32_t generation;

	if (!freeList.empty()) {
	  id = freeList.back();
	  freeList.pop_back();
	  generation = entries[id].generation;
	  entries[id] = {data, generation};
	} else {
	  id = static_cast<uint32_t>(entries.size());
	  generation = 0;
	  entries.push_back({data, generation});
	}

	return Handle{id, generation};
  }

  std::optional<T> remove(Handle handle) {
	if (isValid(handle)) {
	  entries[handle.id].generation++;
	  freeList.push_back(handle.id);
	  return std::exchange(entries[handle.id].data, std::nullopt);
	} else {
	  return std::nullopt;
	}
  }

  bool isValid(Handle handle) const {
	return handle.id < entries.size() &&
		   entries[handle.id].generation == handle.generation &&
		   entries[handle.id].data;
  }

  T &get(Handle handle) {
	assert(isValid(handle));
	return entries[handle.id].data.value();
  }

  const T &get(Handle handle) const {
	assert(isValid(handle));
	return entries[handle.id].data;
  }

  // Iterator implementation
  class Iterator {
  public:
	using iterator_category = std::forward_iterator_tag;
	using difference_type = std::ptrdiff_t;
	using value_type = T;
	using pointer = T *;
	using reference = T &;

	Iterator(GenerationalPool<T> &pool, std::size_t index)
		: pool_(pool), index_(index) {
	  advanceToValid();
	}

	reference operator*() const { return pool_.entries[index_].data; }
	pointer operator->() { return &pool_.entries[index_].data; }

	Iterator &operator++() {
	  ++index_;
	  advanceToValid();
	  return *this;
	}

	Iterator operator++(int) {
	  Iterator tmp = *this;
	  ++(*this);
	  return tmp;
	}

	friend bool operator==(const Iterator &a, const Iterator &b) {
	  return &a.pool_ == &b.pool_ && a.index_ == b.index_;
	};

	friend bool operator!=(const Iterator &a, const Iterator &b) {
	  return !(a == b);
	};

  private:
	GenerationalPool<T> &pool_;
	std::size_t index_;

	void advanceToValid() {
	  while (index_ < pool_.entries.size() && !pool_.entries[index_].alive) {
		++index_;
	  }
	}
  };

  Iterator begin() { return Iterator(*this, 0); }

  Iterator end() { return Iterator(*this, entries.size()); }
};
