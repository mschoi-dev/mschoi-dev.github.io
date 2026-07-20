// Client-side image compression (canvas → JPEG).
// Returns the original file when compression wouldn't help (already small,
// non-image, or animated gif).
async function compressImage(file, maxDim = 2560, quality = 0.88) {
  if (!file || !file.type.startsWith('image/') || file.type === 'image/gif') return file;
  let img;
  const url = URL.createObjectURL(file);
  try {
    img = await new Promise((res, rej) => {
      const i = new Image();
      i.onload = () => res(i);
      i.onerror = rej;
      i.src = url;
    });
  } catch (_) {
    URL.revokeObjectURL(url);
    return file;
  }
  const scale = Math.min(1, maxDim / Math.max(img.width, img.height));
  const w = Math.round(img.width * scale);
  const h = Math.round(img.height * scale);
  const canvas = document.createElement('canvas');
  canvas.width = w; canvas.height = h;
  canvas.getContext('2d').drawImage(img, 0, 0, w, h);
  URL.revokeObjectURL(url);
  const blob = await new Promise(res => canvas.toBlob(res, 'image/jpeg', quality));
  if (!blob || blob.size >= file.size) return file;
  return new File([blob], file.name.replace(/\.\w+$/, '') + '.jpg', { type: 'image/jpeg' });
}
