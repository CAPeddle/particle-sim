#pragma once

#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>

/// @brief Wraps a CUDA API call; prints file/line context and aborts on failure.
///
/// @details
/// - In debug builds this provides immediate, actionable error output.
/// - Production callers that need softer handling should check cudaGetLastError()
///   directly — this macro is intentionally hard-fail (Fail-Fast policy).
///
/// @note Do NOT call this inside destructors marked `noexcept` where abort is
///       unacceptable. Use the raw cudaError_t check instead and log + no-op.
// NOLINTNEXTLINE(cppcoreguidelines-macro-usage)
#define CUDA_CHECK(call)                                                                                               \
    do                                                                                                                 \
    {                                                                                                                  \
        cudaError_t err__ = (call);                                                                                    \
        if (err__ != cudaSuccess)                                                                                      \
        {                                                                                                              \
            std::fprintf(stderr, "CUDA error at %s:%d: %s\n", __FILE__, __LINE__, cudaGetErrorString(err__));          \
            std::abort();                                                                                              \
        }                                                                                                              \
    } while (0)

namespace psim::core
{

/// @brief RAII wrapper for a CUDA device memory allocation.
///
/// Owns a single contiguous device allocation of `count` elements of type `T`.
/// Move-only; copying is disabled.
///
/// @tparam T Element type. Must be trivially destructible (device memory does not
///           invoke destructors).
///
/// @note Thread-safety: Not thread-safe. External synchronisation required if
///       shared across host threads.
template <typename T>
class CudaBuffer
{
public:
    /// @brief Default constructor — creates an empty (null) buffer.
    CudaBuffer() = default;

    /// @brief Allocates device memory for `count` elements.
    ///
    /// @param count Number of elements to allocate.
    /// @pre count > 0.
    explicit CudaBuffer(std::size_t count) { allocate(count); }

    /// @brief Frees device memory if allocated.
    ~CudaBuffer() { free(); }

    CudaBuffer(const CudaBuffer&) = delete;
    CudaBuffer& operator=(const CudaBuffer&) = delete;

    CudaBuffer(CudaBuffer&& other) noexcept
        : ptr_{other.ptr_},
          count_{other.count_}
    {
        other.ptr_ = nullptr;
        other.count_ = 0;
    }

    CudaBuffer& operator=(CudaBuffer&& other) noexcept
    {
        if (this != &other)
        {
            free();
            ptr_ = other.ptr_;
            count_ = other.count_;
            other.ptr_ = nullptr;
            other.count_ = 0;
        }
        return *this;
    }

    /// @brief Allocates (or reallocates) device memory for `count` elements.
    ///
    /// @details Frees any prior allocation before allocating.
    ///
    /// @param count Number of elements to allocate.
    /// @pre count > 0.
    void allocate(std::size_t count)
    {
        free();
        CUDA_CHECK(cudaMalloc(&ptr_, count * sizeof(T)));
        count_ = count;
    }

    /// @brief Frees device memory.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    ///
    /// @note Swallows CUDA errors on free (driver already unloaded at shutdown).
    void free() noexcept
    {
        if (ptr_ != nullptr)
        {
            cudaFree(ptr_); // NOLINT(bugprone-unused-return-value)
            ptr_ = nullptr;
            count_ = 0;
        }
    }

    /// @brief Raw device pointer. May be null if the buffer is empty.
    [[nodiscard]] T* get() const noexcept { return ptr_; }

    /// @brief Number of elements in the allocation.
    [[nodiscard]] std::size_t count() const noexcept { return count_; }

    /// @brief Returns true if no memory is allocated.
    [[nodiscard]] bool empty() const noexcept { return count_ == 0; }

private:
    T* ptr_ = nullptr;
    std::size_t count_ = 0;
};

} // namespace psim::core
