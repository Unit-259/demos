## 🕵️ Spoofed Tweet Examples

These tricks work on GitHub Pages or any site that does **not** automatically render tweets (so the raw link text is displayed).  
They demonstrate how Tweet URLs can be manipulated to **spoof attribution**.

---

### ✅ Real Tweet
My actual tweet and its real Tweet ID:  
🔗 https://x.com/I_Am_Jakoby/status/1965437326420517060  

---

### ⚠️ Spoofed Tweet (Username Ignored)
Same Tweet ID as above, but with a different profile in the URL:  
🔗 https://x.com/IceSolst/status/1965437326420517060  

> The tweet still resolves correctly, even though the username does not belong to that tweet.  

---

### 🎭 Variant 1: Single Leading-Zero Stealth
If you prefix the Tweet ID with a single `0`, the spoofed profile **stays in the URL** instead of snapping back to canonical.  

Credit: [@fbi__open__up](https://x.com/fbi__open__up)  

🔗 https://x.com/IceSolst/status/01965437326420517060  

---

### 🔍 Variant 2: Query Strings Persist
Spoofed Tweet URLs can include arbitrary query strings, which are not stripped.  

Example:  
🔗 https://x.com/I_Am_Jakoby/status/01966555997134016848?q=1  

> Attackers can append tracking identifiers (`?uid=123`), use them for OOB signaling, or bypass filters that expect clean URLs.  

---

### 🎭 Variant 3: Homoglyph Usernames
Credit: [@bettersafetynet (Mick Douglas)](https://x.com/bettersafetynet)  

Twitter usernames allow Unicode homoglyphs (characters that look identical).  

Example (Cyrillic `о` vs Latin `o`):  
- Real: `https://x.com/microsoft/status/...`  
- Fake: `https://x.com/microsоft/status/...`  

> To the human eye, these look the same — but the spoofed link can point to any Tweet ID.  
> Combined with the spoofing trick, this allows **pixel-perfect impersonation**.  

---

### 🖼️ Variant 4: Media URL Canonicalization
The padded-zero trick also works on Tweet media subresources such as `/photo/1`.  

Example:  
- Normal: https://x.com/elon/status/1966555997134016848/photo/1  
- Padded: https://x.com/elon/status/01966555997134016848  

> Spoofing isn’t limited to base tweets — it extends to tweets with **images/media attachments**, making phishing attempts more convincing.  

---

### 💡 Why This Matters
- `{username}` in the URL is ignored → **any profile can appear as author**.  
- Tweet IDs accept a **leading zero**, making spoofed URLs more stealthy.  
- Query strings persist → useful for **tracking, OOB beacons, and filter bypass**.  
- Homoglyph usernames → enable **pixel-perfect impersonation**.  
- Media subresources (`/photo/1`) → spoofing works on **tweets with images** too.  

⚠️ Together, these behaviors show a **systemic lack of canonicalization and validation** in Tweet URLs, enabling phishing, fraud, disinformation, and metadata leakage.  
