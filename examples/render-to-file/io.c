/* render-to-file 的最小文件写入桥(仅 native target 编译)。
 * MoonBit String 在 native ABI 上是 UTF-16 码元裸指针(moonbit_string_t),
 * Bytes 是字节数组裸指针;两侧长度由 MoonBit 显式传入。 */
#include <stdint.h>
#include <stdio.h>
#include <wchar.h>

int32_t moondsp_write_file(
    const uint16_t *path,
    int32_t path_units,
    const uint8_t *data,
    int32_t data_len) {
  if (path_units <= 0 || path_units >= 1024 || data_len < 0) {
    return -3;
  }
  wchar_t wpath[1024];
  for (int32_t i = 0; i < path_units; i++) {
    wpath[i] = (wchar_t)path[i];
  }
  wpath[path_units] = 0;
  FILE *f = _wfopen(wpath, L"wb");
  if (!f) {
    return -1;
  }
  size_t wrote = fwrite(data, 1, (size_t)data_len, f);
  fclose(f);
  return wrote == (size_t)data_len ? 0 : -4;
}
