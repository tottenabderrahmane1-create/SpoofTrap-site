const fallbackRelease = {
  version: "1.5.0",
  generatedAt: "2026-04-05T09:45:00Z",
  artifacts: {
    pkg: {
      file: "SpoofTrap.pkg",
      sha256: "c60655e70d0f4f756d2291fea8d06add877002d0757107aaf0122ee915be1dd4",
    },
    zip: {
      file: "SpoofTrap.zip",
      sha256: "3d22d6e10e8cdae81125c753e5c3714874bd3664a1a59edb11596561e23876b7",
    },
    dmg: {
      file: "SpoofTrap.dmg",
      sha256: "12359b4a1baff191b5ef7160db6b7836d5d761ec18cfecf862287f116ad04ff6",
    },
  },
};

function updateDownloadUi(release, distBase) {
  const version = release?.version || fallbackRelease.version;
  const pkg = release?.artifacts?.pkg || fallbackRelease.artifacts.pkg;
  const zip = release?.artifacts?.zip || fallbackRelease.artifacts.zip;
  const dmg = release?.artifacts?.dmg || fallbackRelease.artifacts.dmg;
  const generatedAt = release?.generatedAt
    ? new Date(release.generatedAt).toLocaleString(undefined, {
        year: "numeric",
        month: "long",
        day: "numeric",
      })
    : null;

  document.getElementById("version-label").textContent = `v${version}`;
  document.getElementById("generated-at").textContent = generatedAt
    ? `Packaged on ${generatedAt}.`
    : "Packaged for macOS distribution.";

  const pkgLink = document.getElementById("pkg-link");
  const zipLink = document.getElementById("zip-link");
  const dmgLink = document.getElementById("dmg-link");

  pkgLink.href = `${distBase}/${pkg.file}`;
  zipLink.href = `${distBase}/${zip.file}`;
  dmgLink.href = `${distBase}/${dmg.file}`;

  document.getElementById("pkg-file").textContent = pkg.file;
  document.getElementById("zip-file").textContent = zip.file;
  document.getElementById("dmg-file").textContent = dmg.file;

  const pkgSha = document.getElementById("pkg-sha");
  const zipSha = document.getElementById("zip-sha");
  const dmgSha = document.getElementById("dmg-sha");

  if (pkgSha) {
    pkgSha.textContent = pkg.sha256;
  }

  if (zipSha) {
    zipSha.textContent = zip.sha256;
  }

  if (dmgSha) {
    dmgSha.textContent = dmg.sha256;
  }
}

async function resolveRelease() {
  const distBases = ["./dist", "../dist"];

  for (const distBase of distBases) {
    try {
      const response = await fetch(`${distBase}/latest.json`);
      if (!response.ok) {
        continue;
      }

      const release = await response.json();
      return { release, distBase };
    } catch {
      // Try the next candidate.
    }
  }

  return { release: fallbackRelease, distBase: "../dist" };
}

resolveRelease().then(({ release, distBase }) => {
  updateDownloadUi(release, distBase);
});
