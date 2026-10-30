// Expo config plugin: signs Android release builds with the Garad AI upload key.
//
// The key is never committed. CI (or a developer machine) provides it through
// environment variables at build time:
//   GARAD_UPLOAD_STORE_FILE      absolute path to the .jks/.keystore file
//   GARAD_UPLOAD_STORE_PASSWORD
//   GARAD_UPLOAD_KEY_ALIAS
//   GARAD_UPLOAD_KEY_PASSWORD
// Without GARAD_UPLOAD_STORE_FILE the release build falls back to the debug key,
// which installs on devices for testing but is rejected by Google Play.
const { withAppBuildGradle } = require('expo/config-plugins');

const MARKER = '// garad-release-signing';

const RELEASE_SIGNING_CONFIG = `
        release { ${MARKER}
            if (System.getenv("GARAD_UPLOAD_STORE_FILE")) {
                storeFile file(System.getenv("GARAD_UPLOAD_STORE_FILE"))
                storePassword System.getenv("GARAD_UPLOAD_STORE_PASSWORD")
                keyAlias System.getenv("GARAD_UPLOAD_KEY_ALIAS")
                keyPassword System.getenv("GARAD_UPLOAD_KEY_PASSWORD")
            }
        }`;

function applyReleaseSigning(gradle) {
  if (gradle.includes(MARKER)) return gradle;

  const signingConfigs = /signingConfigs\s*\{/;
  if (!signingConfigs.test(gradle)) {
    throw new Error('withReleaseSigning: signingConfigs block not found in app/build.gradle');
  }
  let result = gradle.replace(signingConfigs, (match) => match + RELEASE_SIGNING_CONFIG);

  const releaseBuildType = /(buildTypes\s*\{[\s\S]*?release\s*\{[\s\S]*?)signingConfig signingConfigs\.debug/;
  if (!releaseBuildType.test(result)) {
    throw new Error('withReleaseSigning: release build type signingConfig not found in app/build.gradle');
  }
  result = result.replace(
    releaseBuildType,
    '$1signingConfig System.getenv("GARAD_UPLOAD_STORE_FILE") ? signingConfigs.release : signingConfigs.debug'
  );
  return result;
}

module.exports = function withReleaseSigning(config) {
  return withAppBuildGradle(config, (mod) => {
    if (mod.modResults.language !== 'groovy') {
      throw new Error('withReleaseSigning: only Groovy app/build.gradle is supported');
    }
    mod.modResults.contents = applyReleaseSigning(mod.modResults.contents);
    return mod;
  });
};
