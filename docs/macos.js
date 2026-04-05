const macosFallbackRelease = {
  version: "1.5.1",
  generatedAt: "2026-04-05T10:15:00Z",
  artifacts: {
    pkg: {
      file: "SpoofTrap.pkg",
    },
    zip: {
      file: "SpoofTrap.zip",
    },
    dmg: {
      file: "SpoofTrap.dmg",
    },
  },
};

function updateMacosPage(release, distBase) {
  const version = release?.version || macosFallbackRelease.version;
  const pkg = release?.artifacts?.pkg || macosFallbackRelease.artifacts.pkg;
  const zip = release?.artifacts?.zip || macosFallbackRelease.artifacts.zip;
  const dmg = release?.artifacts?.dmg || macosFallbackRelease.artifacts.dmg;
  const generatedAt = release?.generatedAt
    ? new Date(release.generatedAt).toLocaleString(undefined, {
        year: "numeric",
        month: "long",
        day: "numeric",
      })
    : null;

  document.getElementById("macos-version-label").textContent = `v${version}`;
  document.getElementById("macos-generated-at").textContent = generatedAt
    ? `Packaged on ${generatedAt}.`
    : "Packaged for macOS distribution.";

  document.getElementById("macos-dmg-file").textContent = dmg.file;
  document.getElementById("macos-pkg-file").textContent = pkg.file;
  document.getElementById("macos-zip-file").textContent = zip.file;

  const dmgHref = `${distBase}/${dmg.file}`;
  const pkgHref = `${distBase}/${pkg.file}`;

  document.getElementById("macos-dmg-hero").href = dmgHref;
  document.getElementById("macos-dmg-link").href = dmgHref;
  document.getElementById("macos-pkg-link").href = pkgHref;
}

async function resolveMacosRelease() {
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

  return { release: macosFallbackRelease, distBase: "../dist" };
}

resolveMacosRelease().then(({ release, distBase }) => {
  updateMacosPage(release, distBase);
});
