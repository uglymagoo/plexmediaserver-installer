# PMS on Debian armhf and arm64

## What's this all about?

This project can be used to generate a hacky, non-standard compliant Debian package for the armhf and arm64 architecture. It works surprisingly well and fetches the binaries of some NAS builds from the Plex Inc. server.

## What do I have to do?

1. Clone the repo
2. Create a clean working copy, like: `mkdir ../1.8.4-installer; git archive master | tar -x -C ../1.8.4-installer/`
3. Build the package: `cd ..; fakeroot dpkg-deb --build 1.8.4-installer ./`

## How do I build a package for version X.Y.Z?

Just adapt `DEBIAN/postinst` to your needs: download the NAS package from plex.tv, generate the SHA256 hash with `sha256sum <file>`, replace the appropriate URL and HASH in `DEBIAN/postinst` with the new values. Then change the version in `DEBIAN/control` and see the above section for the package creation procedure.
