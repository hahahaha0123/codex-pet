"""Encode existing generated PNG frames as GIFs. No painted/generated image edits."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
LABELS = {
    'greet': '举手打招呼', 'happy': '开心跳跃', 'run': '迈步奔跑',
    'runRight': '向右奔跑', 'stretch': '抬臂伸懒腰', 'bow': '鞠躬致意',
    'work': '托腮思考', 'shy': '捧脸害羞', 'laugh': '捧腹大笑',
    'surprise': '后仰惊讶', 'angry': '叉腰生气', 'cry': '揉眼哭泣',
    'yawn': '坐着打哈欠', 'sleep': '蜷身睡觉', 'hug': '拥抱代码方块',
    'hold': '双手托代码方块',
}
out = ROOT / 'GIF动作'
out.mkdir(exist_ok=True)
manifest = []
for key, label in LABELS.items():
    sources = sorted((ROOT / 'assets' / 'animations' / key).glob('*.png'))
    assert len(sources) == 6, (key, len(sources))
    frames = []
    hashes = set()
    for path in sources:
        with Image.open(path) as source:
            rgba = source.convert('RGBA')
        hashes.add(hashlib.sha256(rgba.tobytes()).hexdigest())
        alpha = rgba.getchannel('A')
        transparent = sum(n for value, n in enumerate(alpha.histogram()) if value < 128)
        assert transparent > rgba.width * rgba.height * 0.15, f'{key}: background not transparent'
        # GIF palette conversion only, reserve color 255 for binary transparency.
        pal = rgba.convert('RGB').quantize(colors=255, method=Image.Quantize.MEDIANCUT)
        pal.paste(255, mask=alpha.point(lambda value: 255 if value < 128 else 0))
        pal.info['transparency'] = 255
        frames.append(pal)
    assert len(hashes) >= 5, f'{key}: not enough distinct drawings'
    duration = 260 if key == 'sleep' else 180
    destination = out / f'{label}.gif'
    frames[0].save(destination, save_all=True, append_images=frames[1:],
                   duration=duration, loop=0, disposal=2, transparency=255, optimize=False)
    with Image.open(destination) as result:
        assert result.n_frames == 6, (key, result.n_frames)
        assert result.info['loop'] == 0
        for index in range(result.n_frames):
            result.seek(index)
            assert result.info['duration'] == duration
    manifest.append({'key': key, 'label': label, 'file': f'GIF动作/{label}.gif',
                     'frames': 6, 'durationMs': duration, 'uniqueFrames': len(hashes),
                     'width': frames[0].width, 'height': frames[0].height})
    print(f'PASS {label}: 6 distinct frames, transparent, infinite loop')
(ROOT / 'assets' / 'animations.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8-sig')
cards = ''.join(f'<figure><img src="{m["file"]}" alt="{m["label"]}"><figcaption>{m["label"]} <small>6 帧 · 循环</small></figcaption></figure>' for m in manifest)
html = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>小柯 · 16 动作 GIF</title>
<style>body{margin:0;background:#131e21;color:#d4f5e8;font:15px "Microsoft YaHei",sans-serif;padding:36px}h1{font-size:26px}p{color:#8db3a5}.grid{display:grid;grid-template-columns:repeat(4,minmax(180px,1fr));gap:16px;max-width:1200px}figure{margin:0;background:#1c2b2f;border:1px solid #36554e;border-radius:18px;text-align:center;padding:12px}img{width:100%;height:240px;object-fit:contain}figcaption{padding:12px}small{display:block;color:#8db3a5;font-size:11px;margin-top:6px}</style>
<h1>CODEX / 小柯</h1><p>16 个动作 · 连续手绘帧 · 透明背景 GIF · 原创角色</p><div class="grid">'''+cards+'</div></html>'
(ROOT / '动作预览.html').write_text(html, encoding='utf-8')
