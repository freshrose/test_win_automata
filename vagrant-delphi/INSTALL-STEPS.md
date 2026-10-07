# Delphi 13.1 install — VM steps

The VM **`delphi-build`** is a clean Windows 10 desktop, auto-logged-in as
`vagrant`, hostname pinned to **`delphi-build`** (the license binds to this name
— do not rename it).

## Connect
- Open **Hyper-V Manager** → double-click **`delphi-build`** → **Connect**.
- If you see a lock/login screen, sign in as **`vagrant`** / **`vagrant`**
  (autologon isn't reliable on this box; manual login is fine).
- VM IP (if you prefer RDP): `172.24.98.163`, user `vagrant`, pass `vagrant`.

## Install Delphi
1. On the desktop, run **"Install Delphi 13.1"** (or `C:\delphi-setup\setup.exe`).
   - This is your ESD installer, already staged from the host — no need to re-download.
2. In the installer:
   - **Sign in** with your Embarcadero account (`radek.uldrych@rsm.cz`) **or** enter
     the **serial** `2UHK-7TSFU2-LURMB7-D28D` when prompted.
   - Platforms: select **Delphi** + **Windows 32-bit** and **Windows 64-bit** only
     (leave the rest off → faster, smaller).
   - Let it download + install.
3. **Activate / register** the license (the installer or License Manager will do
   this online). Confirm it shows as registered.
4. Optional sanity check (in a Developer Command Prompt or any cmd):
   ```
   "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc32.exe" --version
   ```

## When done
Tell me "install done" and I'll capture the install from the VM (it's reachable
over WinRM + the `C:\host` share back to the host) and bake the clean Docker
build image. Nothing else for you to do.

> The `C:\host` folder in the VM is the exchange share; I'll write the capture to
> `C:\host\out`, which lands on the host at `C:\Users\rosa\dbuild\vmshare\out`.
