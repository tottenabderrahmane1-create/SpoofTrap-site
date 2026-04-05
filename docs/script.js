const fallbackRelease = {
  version: "1.6.0",
  generatedAt: "2026-03-29T12:00:00Z",
  artifacts: {
    pkg: {
      file: "SpoofTrap.pkg",
      sha256: "a83de0f24ac79d6885f4c0014c1cc049033132853b9786c600b0e55a90e356da",
    },
    zip: {
      file: "SpoofTrap.zip",
      sha256: "18c4ba38c4729c58c0c2b6c82d017aede4f1e8badd4cac8c4c16881ad53a44f1",
    },
    dmg: {
      file: "SpoofTrap.dmg",
      sha256: "c15791ea415813f7a7d7eee36b3f88461a11569add96d0fe9c56414411d6e4af",
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
