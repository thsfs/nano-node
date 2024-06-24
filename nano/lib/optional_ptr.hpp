#pragma once

#include <nano/lib/locks.hpp>
#include <nano/lib/utility.hpp>

#include <cstddef>
#include <memory>

namespace nano
{
/**
 * A space efficient optional which does heap allocation when needed.
 * This is an alternative to boost/std::optional when the value type is
 * large and often not present.
 *
 * optional_ptr is similar to using std::unique_ptr as an optional, with the
 * main difference being that it's copyable.
 */
template <typename T>
class optional_ptr final
{
	static_assert (sizeof (T) > alignof (std::max_align_t), "Use [std|boost]::optional");

public:
	explicit optional_ptr ()
	{
		nano::lock_guard<nano::mutex> lock{ mutex };
		ptr = nullptr;
	}

	explicit optional_ptr (T const & value)
	{
		nano::lock_guard<nano::mutex> lock{ mutex };
		ptr = std::make_unique<T> (value);
	}

	explicit optional_ptr (optional_ptr const & other)
	{
		nano::lock_guard<nano::mutex> lock{ mutex };
		ptr = (other && other.ptr) ? std::make_unique<T> (*other.ptr) : nullptr;
	}

	optional_ptr & operator= (optional_ptr const & other)
	{
		nano::lock_guard<nano::mutex> lock{ mutex };
		if (other && other.ptr)
		{
			ptr = std::make_unique<T> (*other.ptr);
		}
		return *this;
	}

	optional_ptr & operator= (T const & t_object)
	{
		auto new_ptr = std::make_unique<T> (t_object);
		nano::lock_guard<nano::mutex> lock{ mutex };
		ptr.swap (new_ptr);
		return *this;
	}

	~optional_ptr ()
	{
		nano::lock_guard<nano::mutex> lock{ mutex };
		ptr.reset (nullptr);
	}

	T & operator* ()
	{
		nano::lock_guard<nano::mutex> lock{ mutex };
		return *ptr;
	}

	T const & operator* () const
	{
		nano::lock_guard<nano::mutex> lock{ mutex };
		return *ptr;
	}

	T * const operator-> ()
	{
		nano::lock_guard<nano::mutex> lock{ mutex };
		return ptr.operator-> ();
	}

	T const * const operator-> () const
	{
		nano::lock_guard<nano::mutex> lock{ mutex };
		return ptr.operator-> ();
	}

	T const * const get () const
	{
		nano::lock_guard<nano::mutex> lock{ mutex };
		debug_assert (is_initialized ());
		return ptr.get ();
	}

	T * const get ()
	{
		nano::lock_guard<nano::mutex> lock{ mutex };
		debug_assert (is_initialized ());
		return ptr.get ();
	}

	explicit operator bool () const
	{
		nano::lock_guard<nano::mutex> lock{ mutex };
		return static_cast<bool> (ptr);
	}

	[[nodiscard]] bool is_initialized () const
	{
		nano::lock_guard<nano::mutex> lock{ mutex };
		return static_cast<bool> (ptr);
	}

private:
	std::unique_ptr<T> ptr;
	mutable nano::mutex mutex;
};
}
