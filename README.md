
# rr-apt

This repository hosts a simple Debian/APT repository (served via GitHub Pages) for ROS packages used by the `kilted` project. It contains the Debian layout under `dists/` and `pool/`, plus the repository signing key `public.gpg`.

Use the following to add the repository and install the package:

```bash
# One-time setup (if not already done)
curl -fsSL https://ryder-robots.github.io/rr-apt/public.gpg | sudo gpg --dearmor -o /usr/share/keyrings/rr-apt.gpg
echo "deb [signed-by=/usr/share/keyrings/rr-apt.gpg] https://ryder-robots.github.io/rr-apt noble main" | sudo tee /etc/apt/sources.list.d/rr-apt.list

# Install
sudo apt update
sudo apt install ros-kilted-rr-interfaces
```

```
updating releases

./build-and-publish.sh ~/ros2_ws/src/rr_interfaces
```

Repository layout highlights:

- `dists/` — distribution metadata and Release files.
- `pool/` — package archives.
- `public.gpg` — the repository GPG public key.

Replace `youruser` with the GitHub Pages username hosting this repo.
