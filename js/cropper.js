// Circular avatar cropper — shows the photo inside the actual circle,
// drag to reposition, slider/wheel to zoom, exports a high-quality
// square JPEG of exactly what was previewed.
// Usage: const file = await openCropper(rawFile, { maxOut: 1600 });
function openCropper(file, opts = {}) {
  const maxOut = opts.maxOut || 1600;
  return new Promise(resolve => {
    if (!file || !file.type.startsWith('image/')) return resolve(file);
    const url = URL.createObjectURL(file);
    const img = new Image();

    img.onload = () => {
      const S = Math.min(340, window.innerWidth - 64);
      const wrap = document.createElement('div');
      wrap.className = 'crop-modal';
      wrap.innerHTML = `
        <div class="crop-box">
          <p class="crop-title">Adjust your photo</p>
          <canvas class="crop-canvas" width="${S}" height="${S}"></canvas>
          <div class="crop-zoom-row">
            <span class="crop-zoom-ico">－</span>
            <input type="range" class="crop-zoom" min="0" max="100" value="0" aria-label="Zoom">
            <span class="crop-zoom-ico">＋</span>
          </div>
          <p class="crop-hint">Drag to reposition · slide to zoom</p>
          <div class="crop-actions">
            <button type="button" class="btn crop-cancel">Cancel</button>
            <button type="button" class="btn btn-primary crop-ok">Use photo</button>
          </div>
        </div>`;
      document.body.appendChild(wrap);
      document.body.style.overflow = 'hidden';

      const canvas = wrap.querySelector('canvas');
      const ctx = canvas.getContext('2d');
      const W = img.naturalWidth, H = img.naturalHeight;
      const minScale = Math.max(S / W, S / H);
      const maxScale = Math.max(minScale * 5, 1);
      let scale = minScale;
      let ox = (S - W * scale) / 2;
      let oy = (S - H * scale) / 2;

      function clamp() {
        ox = Math.min(0, Math.max(S - W * scale, ox));
        oy = Math.min(0, Math.max(S - H * scale, oy));
      }
      function draw() {
        ctx.clearRect(0, 0, S, S);
        ctx.imageSmoothingQuality = 'high';
        ctx.drawImage(img, ox, oy, W * scale, H * scale);
        ctx.save();
        ctx.fillStyle = 'rgba(0,0,0,0.55)';
        ctx.beginPath();
        ctx.rect(0, 0, S, S);
        ctx.arc(S / 2, S / 2, S / 2 - 1, 0, Math.PI * 2, true);
        ctx.fill('evenodd');
        ctx.strokeStyle = 'rgba(255,255,255,0.95)';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(S / 2, S / 2, S / 2 - 1, 0, Math.PI * 2);
        ctx.stroke();
        ctx.restore();
      }
      draw();

      const zoom = wrap.querySelector('.crop-zoom');
      function setScale(ns) {
        ns = Math.min(maxScale, Math.max(minScale, ns));
        const c = S / 2;
        ox = c - (c - ox) * (ns / scale);
        oy = c - (c - oy) * (ns / scale);
        scale = ns;
        clamp(); draw();
      }
      zoom.oninput = () => {
        const t = zoom.value / 100;
        setScale(minScale * Math.pow(maxScale / minScale, t));
      };
      canvas.addEventListener('wheel', e => {
        e.preventDefault();
        setScale(scale * (e.deltaY < 0 ? 1.08 : 1 / 1.08));
        const t = Math.log(scale / minScale) / Math.log(maxScale / minScale);
        zoom.value = Math.round(Math.min(1, Math.max(0, t)) * 100);
      }, { passive: false });

      let dragging = false, lx = 0, ly = 0;
      canvas.style.touchAction = 'none';
      canvas.onpointerdown = e => {
        dragging = true; lx = e.clientX; ly = e.clientY;
        canvas.setPointerCapture(e.pointerId);
      };
      canvas.onpointermove = e => {
        if (!dragging) return;
        ox += e.clientX - lx; oy += e.clientY - ly;
        lx = e.clientX; ly = e.clientY;
        clamp(); draw();
      };
      canvas.onpointerup = canvas.onpointercancel = () => { dragging = false; };

      function close(result) {
        URL.revokeObjectURL(url);
        wrap.remove();
        document.body.style.overflow = '';
        resolve(result);
      }
      wrap.querySelector('.crop-cancel').onclick = () => close(null);
      wrap.querySelector('.crop-ok').onclick = () => {
        const srcSize = S / scale;                       // crop square in source pixels
        const out = Math.max(64, Math.min(maxOut, Math.round(srcSize)));
        const oc = document.createElement('canvas');
        oc.width = out; oc.height = out;
        const octx = oc.getContext('2d');
        octx.imageSmoothingQuality = 'high';
        octx.drawImage(img, -ox / scale, -oy / scale, srcSize, srcSize, 0, 0, out, out);
        oc.toBlob(b => {
          if (!b) return close(null);
          close(new File([b], file.name.replace(/\.\w+$/, '') + '_avatar.jpg', { type: 'image/jpeg' }));
        }, 'image/jpeg', 0.95);
      };
    };

    img.onerror = () => { URL.revokeObjectURL(url); resolve(file); };
    img.src = url;
  });
}
