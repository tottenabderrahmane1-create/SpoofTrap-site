const fallbackRelease = {
  version: "1.5.1",
  generatedAt: "2026-04-05T10:15:00Z",
  artifacts: {
    pkg: {
      file: "SpoofTrap.pkg",
      sha256: "ccb3ec8483aaec8eea38f63533298d32568aed8e9f474f8a02aecef40d0c2133",
    },
    zip: {
      file: "SpoofTrap.zip",
      sha256: "bd6fb888452113e615e1b1bb2152cfd15dce9f16b15141438612aa230d180e2b",
    },
    dmg: {
      file: "SpoofTrap.dmg",
      sha256: "d2ebfedb7cb433b47e6b94d07e20d752dc5c7616a6cd07b90018c249c47dbce0",
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
