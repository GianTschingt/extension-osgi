package org.lucee.extension.osgi;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.osgi.framework.BundleException;
import org.osgi.framework.Version;
import org.osgi.framework.VersionRange;

class VersionHandlingTest {

	@ParameterizedTest(name = "{0} pre-release={1}")
	@CsvSource({
		"33.8.0-jre, false",
		"33.8.0-android, false",
		"1.0.0.Final, false",
		"1.0.0.RELEASE, false",
		"1.2.3.sp1, false",
		"1.0.0.v20230101, false",
		"2.17.0, false",
		"2.0.0-M1, true",
		"5.4.0.Beta2, true",
		"3.0-rc5, true",
		"1.0-SNAPSHOT, true",
		"1.0.0-ALPHA, true"
	})
	void isPreReleaseTable(String version, boolean expected) {
		assertEquals(expected, BundleProvider.isPreRelease(version), version);
	}

	@Test
	void toRangeFromGreaterEqualAndNotGreaterEqual() {
		VersionRange r = OSGiServiceImpl.toRange("(version>=2.17.0)(!(version>=3.0.0))");
		assertEquals(VersionRange.LEFT_CLOSED, r.getLeftType());
		assertEquals(new Version(2, 17, 0), r.getLeft());
		assertEquals(new Version(3, 0, 0), r.getRight());
		assertEquals(VersionRange.RIGHT_OPEN, r.getRightType());
		assertTrue(r.includes(new Version(2, 17, 0)));
		assertTrue(r.includes(new Version(2, 23, 0)));
		assertFalse(r.includes(new Version(3, 0, 0)));
	}

	@Test
	void toRangeLessOrEqual() {
		VersionRange r = OSGiServiceImpl.toRange("(version<=3.0.0)");
		assertEquals(Version.emptyVersion, r.getLeft());
		assertEquals(VersionRange.LEFT_CLOSED, r.getLeftType());
		assertEquals(new Version(3, 0, 0), r.getRight());
		assertEquals(VersionRange.RIGHT_CLOSED, r.getRightType());
	}

	@Test
	void toRangeNotLessOrEqualIsOpenLowerBound() {
		VersionRange r = OSGiServiceImpl.toRange("(!(version<=2.17.0))");
		assertEquals(new Version(2, 17, 0), r.getLeft());
		assertEquals(VersionRange.LEFT_OPEN, r.getLeftType());
		assertTrue(r.getRight() == null || !r.includes(r.getRight()));
		assertFalse(r.includes(new Version(2, 17, 0)));
		assertTrue(r.includes(new Version(2, 17, 1)));
	}

	@Test
	void toRangeEqualsIsExactVersion() {
		VersionRange r = OSGiServiceImpl.toRange("(version=2.17.0)");
		assertEquals(new Version(2, 17, 0), r.getLeft());
		assertEquals(new Version(2, 17, 0), r.getRight());
		assertEquals(VersionRange.LEFT_CLOSED, r.getLeftType());
		assertEquals(VersionRange.RIGHT_CLOSED, r.getRightType());
		assertTrue(r.includes(new Version(2, 17, 0)));
		assertFalse(r.includes(new Version(2, 17, 1)));
	}

	@Test
	void getMavenVersionsPrefersTheGivenSpelling() throws BundleException {
		List<String> jre = new BundleProvider.BundleDefinition("com.google.guava", "33.8.0-jre").getMavenVersions();
		assertEquals("33.8.0-jre", jre.get(0));
		assertTrue(jre.contains("33.8.0.jre"));

		List<String> shortVersion = new BundleProvider.BundleDefinition("com.google.gson", "2.17.0").getMavenVersions();
		assertEquals("2.17.0", shortVersion.get(0));
		assertTrue(shortVersion.contains("2.17"));
	}

	@Test
	void flavourMatchesJreAndAndroid() {
		assertEquals("jre", BundleProvider.flavour("33.8.0-jre"));
		assertEquals("android", BundleProvider.flavour("33.8.0-android"));
		assertEquals("", BundleProvider.flavour("33.8.0"));
		assertEquals("jre", BundleProvider.flavour(VersionRange.valueOf("[33.8.0.jre,34.0.0)")));
		assertEquals("", BundleProvider.flavour(VersionRange.valueOf("[33.8.0,34.0.0)")));
	}

	@Test
	void unmappedVersionUsesTheClosedLowerBound() {
		assertEquals("2.17.0", OSGiServiceImpl.unmappedVersion(VersionRange.valueOf("[2.17.0,3.0.0)")));
		assertNull(OSGiServiceImpl.unmappedVersion(VersionRange.valueOf("(2.17.0,3.0.0)")));
		assertNull(OSGiServiceImpl.unmappedVersion(null));
	}

	@Test
	void toVersionDocumentsExtraSegmentsAndOverflow() {
		assertEquals(new Version(1, 2, 3, "4_5"), BundleProvider.toVersion("1.2.3.4.5", null));
		assertNull(BundleProvider.toVersion("1.2.20030203000129", null));
		assertEquals(new Version(0, 0, 0), BundleProvider.toVersion("1.2.20030203000129", Version.emptyVersion));
	}
}
