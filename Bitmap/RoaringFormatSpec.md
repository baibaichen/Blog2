### 1. Cookie header

> The cookie header spans either 64 bits or 32 bits followed by a variable number of bytes.
>
> 1. If the first 32 bits take the value SERIAL_COOKIE_NO_RUNCONTAINER, then no container part of the Roaring bitmap can be of type "run" (only array and bitset containers are allowed). When the cookie has this particular value, the next 32 bits are used to store an integer representing the number of containers. If the bitmap is empty (i.e., it has no container), then you should choose this cookie header. In this scenario, the cookie header uses 64 bits.
> 2. The 16 least significant bits of the 32-bit cookie have value SERIAL_COOKIE. In that case, the 16 most significant bits of the 32-bit cookie are used to store the number of containers minus 1. That is, if you shift right by 16 the cookie and add 1, you get the number of containers. Let `size` be the number of containers. Then we store `(size + 7) / 8` bytes, following the initial 32 bits, as a bitset to indicate whether each of the containers is a run container (bit set to 1) or not (bit set to 0). The first (least significant) bit of the first byte corresponds to the first stored container and so forth. In this scenario, the cookie header uses 32 bits followed by `(size + 7) / 8` bytes.
>
> Thus it follows that the least significant 16 bits of the first 32 bits of a serialized bitmaps should either have the value SERIAL_COOKIE_NO_RUNCONTAINER or the value SERIAL_COOKIE. In other cases, we should abort the decoding.
>
> After scanning the cookie header, we know how many containers are present in the bitmap.

**Cookie header** 要么为 64 位，要么为32位，后跟可变数量的字节。

1. 如果前 32 位的值为 `SERIAL_COOKIE_NO_RUNCONTAINER`，则 Roaring 位图的容器部分不能为 **run** 类型（只允许**数组**和**位集**容器）。当 Cookie 具有此特定值时，接下来的 32位用于存储表示容器数量的整数。**如果位图为空（即没有容器）**，则应选择此 Cookie header。在此情况下，Cookie header 为 64 位。
2. 32 位 Cookie 的最低有效 16 位的值为 **SERIAL_COOKIE**。在这种情况下，32 位 Cookie 的最高有效 16 位用于存储**容器数减 1** 的值。**也就是说，如果将 Cookie 向右移动 16 位并加 1，就可以得到容器的数量**。设 size 为容器数量。然后，我们在初始32位之后存储 **(size + 7) / 8** 字节的位集，**用于指示每个容器类型是否为 run 类型**（位设置为1）或不是（位设置为0）。第一个（最低有效）字节的第一个位对应于第一个存储的容器，依此类推。在此情况下，Cookie header 使用 32 位，后跟 <u>(size + 7) / 8</u> 字节。

因此，序列化位图的前 32位 的最低有效 16 位的值应为 `SERIAL_COOKIE_NO_RUNCONTAINER` 或 `SERIAL_COOKIE` 。如果不是，则需要中止解码过程。扫描 Cookie 头部后，我们知道位图中存在多少个容器。

![Format diagram](https://github.com/RoaringBitmap/RoaringFormatSpec/raw/master/diagram.png)

### 2. Descriptive header

> The cookie header is followed by a descriptive header. For each container, we store the key (16 most significant bits) along with the cardinality minus 1, using 16 bits for each value (for a total of 32 bits per container).
>
> Thus, if there are x containers, the descriptive header will contain 32 x bits or 4 x bytes.
>
> After scanning the descriptive header, we know the type of each container. Indeed, if the cookie took value SERIAL_COOKIE, then we had a bitset telling us which containers are run containers; otherwise, we know that there are no run containers. For the containers that are not run containers, then we use the cardinality to determine the type: a cardinality of up and including 4096 indicates an array container whereas a cardinality above 4096 indicates a bitset container.

Cookie 头部之后是一个描述性 header。每个容器使用 32 位存储信息，最高有效16 位保存的是 key，最低有效 16 位保存的是**对应容器的基数值减 1**。

因此，如果有 x 个容器，则描述性头部将包含 **32 * x** 位或 **4 * x** 字节。

扫描完描述性 header后，每个容器的类型就知道了。实际上，如果cookie的值为`SERIAL_COOKIE`，那么有一个位集告诉我们哪些容器是 run 类型的容器；否则，我们知道没有 run 类型的容器。对于非 run 类型的容器，使用基数来确定类型：**基数为 4096 及以下表示数组容器，基数超过 4096 表示位集容器**。

### 3. Offset header

> If and only if one of these is true
>
> 1. the cookie takes value SERIAL_COOKIE_NO_RUNCONTAINER
> 2. the cookie takes the value SERIAL_COOKIE *and* there are at least NO_OFFSET_THRESHOLD containers,
>
> then we store (using a 32-bit value) the location (in bytes) of the container from the beginning of the stream (starting with the cookie) for each container.

当且仅当其中之一为真

1. cookie 的值为 `SERIAL_COOKIE_NO_RUNCONTAINER`
2. cookie 的值为 `SERIAL_COOKIE` **并且**至少有 `NO_OFFSET_THRESHOLD` 个容器，

那么，将使用 32 位的值为每个容器存储相对于流开始（从 cookie 开始）的位置（以字节为单位）。

### 4. Container storage

> The containers are then stored one after the other.
>
> - For array containers, we store a sorted list of 16-bit unsigned integer values corresponding to the array container. So if there are x values in the array container, 2 x bytes are used.
> - Bitset containers are stored using exactly 8KB using a bitset serialized with 64-bit words. Thus, for example, if value j is present, then word j/64 (starting at word 0) will have its (j%64) least significant bit set to 1 (starting at bit 0).
> - A run container is serialized as a 16-bit integer indicating the number of runs, followed by a pair of 16-bit values for each run. Runs are non-overlapping and sorted. Thus a run container with x runs will use 2 + 4 x bytes. Each pair of 16-bit values contains the starting index of the run followed by the length of the run minus 1. That is, we interleave values and lengths, so that if you have the values 11,12,13,14,15, you store that as 11,4 where 4 means that beyond 11 itself, there are 4 contiguous values that follow. Other example: e.g., 1,10, 20,0, 31,2 would be a concise representation of 1, 2, ..., 11, 20, 31, 32, 33

然后，按顺序容器存储。

- 对于**数组容器**，我们存储一个**排序的无符号 16 位整数值列表**，因此，数组容器有 x 个值，则使用 2x 字节。
- 每个位集容器需要 8KB，按 64 位整数序列化位集。因此，例如，如果存在值 j ，则字 **j/64**（从字 0 开始）将使其 (**j%64**) 最低有效位设置为 1（从位 0 开始）。
- Run 类型的容器被序列化为一个 16 位整数，表示 run 的数量，后跟每个run 的一对 16 位值。run 非重叠且有序。因此，具有 x 个 run 的容器将使用 **2 + 4x** 字节。每对 16 位值包含 run 的**起始索引**，后跟run的长度减1。也就是说，我们交错存储值和长度，因此如果有值11,12,13,14,15，则将其存储为11,4，其中4表示除了11本身之外，还有4个连续的值。另一个示例：例如，1,10, 20,0, 31,2是1, 2, ..., 11, 20, 31, 32, 33的简洁表示。
