component extends="org.lucee.cfml.test.LuceeTestCase" labels="osgi" {

	function beforeAll() {
		variables.engine = getPageContext().getConfig().getFactory().getEngine();
		variables.osgi = createObject( "java", "lucee.runtime.osgi.OSGi" );
		// recorded before any test calls setLibraryDirectory, so the availability
		// test still sees the startup state even if later tests load the service
		variables.availableAtStartup = variables.osgi.isAvailable();
		variables.serviceAtStartup = variables.engine.getOSGiService();
		variables.serviceClassAtStartup = variables.serviceAtStartup.getClass().getName();
		variables.service = variables.serviceAtStartup;
		variables.dir = getTempDirectory() & "OSGiExtension" & createUniqueId() & "/";
		directoryCreate( variables.dir );
	}

	function afterAll() {
		if ( directoryExists( variables.dir ) ) directoryDelete( variables.dir, true );
	}

	function run( testResults, testBox ) {
		describe( "OSGi extension", function() {

			it( "has no id and no info for a class that is not from a bundle", function() {
				var clazz = createObject( "java", "java.lang.String" ).getClass();
				expect( isNull( service.getId( clazz ) ) ).toBeTrue();
				expect( isNull( service.getInfo( clazz ) ) ).toBeTrue();
			});

			it( "has no id for the classes of Lucee itself", function() {
				expect( isNull( service.getId( createObject( "java", "lucee.runtime.PageContextImpl" ).getClass() ) ) ).toBeTrue();
			});

			it( "throws for a bundle that does not exist", function() {
				expect( function() {
					service.getClassLoader( "does.not.exist", "1.0.0" );
				} ).toThrow();
			});

		});

		describe( "OSGi service runtime", function() {

			// Guards: core 9.0 never calls OSGi.setLibraryDirectory when the config is
			// essentialOnly (ConfigServerImpl.java:1512-1516). The extension jar is in
			// lib, but the service is never loaded, and core falls back to NoOSGiService
			// / the normal classloader. Existing tests still pass in that situation.
			it( "is actually active (OSGi.isAvailable())", function() {
				if ( !variables.availableAtStartup ) {
					fail( "OSGi service is not active (OSGi.isAvailable() is false, service class is #variables.serviceClassAtStartup#). "
						& "Core 9.0 does not set the lib folder when the config is essentialOnly (ConfigServerImpl.java:1512-1516), "
						& "so the installed OSGi extension is never loaded." );
				}
				if ( findNoCase( "NoOSGiService", variables.serviceClassAtStartup ) ) {
					fail( "OSGi.isAvailable() was true, but the engine still returned #variables.serviceClassAtStartup#. "
						& "Core 9.0 does not set the lib folder when the config is essentialOnly (ConfigServerImpl.java:1512-1516)." );
				}
			});

			// Guards: Felix is started with core's default.properties (from the .lco),
			// which has no system.packages and no osgi.ee capabilities, so a real Maven
			// bundle cannot be resolved (gson fails on osgi.ee=JavaSE, commons-codec on java.io).
			it( "loads the Maven bundle gson 2.10.1 and a class from it works", function() {
				loadServiceFromLibFolder();
				try {
					var clazz = variables.service.loadClass( "com.google.gson", "2.10.1", "com.google.gson.Gson" );
					assertBundleClassWorks( clazz, "com.google.gson", "2.10.1" );
					var gson = clazz.newInstance();
					expect( gson.toJson( "hello" ) ).toBe( '"hello"' );
				}
				catch ( any e ) {
					fail( "Failed to load Maven bundle com.google.gson:2.10.1 through the OSGi service, or a class from it did not work. "
						& "Felix is reading core's default.properties, which has no system.packages or osgi.ee capabilities. "
						& errorText( e ) );
				}
			});

			// Guards: same Felix default.properties problem as gson, with a second
			// Maven bundle (commons-codec fails on a missing java.io package).
			it( "loads the Maven bundle commons-codec 1.17.1 and a class from it works", function() {
				loadServiceFromLibFolder();
				try {
					var clazz = variables.service.loadClass( "org.apache.commons.commons-codec", "1.17.1", "org.apache.commons.codec.digest.DigestUtils" );
					assertBundleClassWorks( clazz, "commons-codec", "1.17.1" );
					var md5Hex = clazz.getMethod( "md5Hex", [ createObject( "java", "java.lang.String" ).getClass() ] );
					expect( md5Hex.invoke( javacast( "null", "" ), [ "abc" ] ) ).toBe( "900150983cd24fb0d6963f7d28e17f72" );
				}
				catch ( any e ) {
					fail( "Failed to load Maven bundle org.apache.commons.commons-codec:1.17.1 through the OSGi service, or a class from it did not work. "
						& "Felix is reading core's default.properties, which has no system.packages or osgi.ee capabilities. "
						& errorText( e ) );
				}
			});

			// Guards: toVersion crashes on Maven suffixes such as 33.8.0-jre
			// (NumberFormatException: For input string: "0-jre"), and getBundleAsURL
			// uses OSGi spelling (dot qualifier) instead of the Maven artifact version
			// (hyphen).
			it( "loads guava 33.8.0-jre and a class from it works", function() {
				loadServiceFromLibFolder();
				try {
					var clazz = variables.service.loadClass( "com.google.guava", "33.8.0-jre", "com.google.common.base.Strings" );
					assertBundleClassWorks( clazz, "com.google.guava", "33.8.0-jre" );
					var isNullOrEmpty = clazz.getMethod( "isNullOrEmpty", [ createObject( "java", "java.lang.String" ).getClass() ] );
					expect( isNullOrEmpty.invoke( javacast( "null", "" ), [ "" ] ) ).toBeTrue();
					expect( isNullOrEmpty.invoke( javacast( "null", "" ), [ "x" ] ) ).toBeFalse();
				}
				catch ( any e ) {
					fail( "Failed to load guava 33.8.0-jre through the OSGi service. "
						& "toVersion cannot parse Maven suffixes such as '-jre' (NumberFormatException: For input string: ""0-jre""), "
						& "and getBundleAsURL uses OSGi spelling instead of the Maven artifact version. "
						& errorText( e ) );
				}
			});

			// Guards: jackson-databind 2.17.0 depends on jackson-annotations [2.17,3).
			// loadMissing does not keep that range: for a package it calls latestVersion,
			// which currently picks the pre-release 3.0-rc5 (maven 'release' / 'latest'),
			// and toVersion then crashes on the suffix. The resolved annotations version
			// must be inside the range and must not be a pre-release.
			it( "resolves jackson-databind 2.17.0's jackson-annotations dependency inside [2.17,3), not a pre-release", function() {
				loadServiceFromLibFolder();
				var clazz = "";
				try {
					clazz = variables.service.loadClass( "com.fasterxml.jackson.core.jackson-databind", "2.17.0", "com.fasterxml.jackson.databind.ObjectMapper" );
				}
				catch ( any e ) {
					fail( "jackson-databind 2.17.0 did not resolve its jackson-annotations dependency to a release inside the range [2.17,3). "
						& "The resolver picks a pre-release such as 3.0-rc5 (the current Maven 'release' / 'latest') or does not honour the range. "
						& errorText( e ) );
				}
				try {
					assertBundleClassWorks( clazz, "jackson-databind", "2.17.0" );
					var annotationsClass = clazz.getClassLoader().loadClass( "com.fasterxml.jackson.annotation.JsonProperty" );
					var info = variables.service.getInfo( annotationsClass );
					if ( isNull( info ) || isNull( info[ "version" ] ) ) {
						fail( "jackson-databind 2.17.0 loaded, but jackson-annotations could not be identified, so the resolved version could not be checked against [2.17,3)." );
					}
					var ver = toString( info[ "version" ] );
					if ( isPreRelease( ver ) || !isVersionInHalfOpenRange( ver, "2.17", "3.0" ) ) {
						fail( "jackson-databind 2.17.0 resolved jackson-annotations to [#ver#], which is outside the range [2.17,3) or is a pre-release. "
							& "The resolver must not pick a pre-release such as 3.0-rc5." );
					}
					var mapper = clazz.newInstance();
					expect( mapper.writeValueAsString( "hello" ) ).toBe( '"hello"' );
				}
				catch ( any e ) {
					if ( findNoCase( "outside the range", e.message ) || findNoCase( "could not be identified", e.message ) || findNoCase( "did not resolve", e.message ) ) {
						rethrow;
					}
					fail( "jackson-databind 2.17.0 did not resolve its jackson-annotations dependency to a release inside the range [2.17,3). "
						& "The resolver picks a pre-release such as 3.0-rc5 (the current Maven 'release' / 'latest') or does not honour the range. "
						& errorText( e ) );
				}
			});

			// Guards: loadMissing's MISSING_BUNDLE pattern captures only the lower bound
			// of bundle-version>=X and passes that string to load() as an exact version,
			// so a locally available 2.17.1 is ignored when the requirement is >=2.17.0.
			it( "does not treat a '>=X' version range as the exact version X", function() {
				loadServiceFromLibFolder();
				var extra = variables.dir & "range" & createUniqueId() & "/";
				directoryCreate( extra );
				var provider = createBundleJar( extra, "lucee.test.vr.provider", "2.17.1" );
				var consumer = createBundleJar( extra, "lucee.test.vr.consumer", "1.0.0", 'Require-Bundle: lucee.test.vr.provider;bundle-version="[2.17.0,99.0.0)"' );
				var File = createObject( "java", "java.io.File" );
				try {
					var cl = variables.service.getClassLoader( "lucee.test.vr.consumer", "1.0.0", [ File.init( extra ) ] );
					if ( isNull( cl ) ) {
						fail( "A '>=2.17.0' requirement did not resolve the locally available 2.17.1 (class loader was null). "
							& "loadMissing must not treat bundle-version>=X as the exact version X." );
					}
					var id = variables.service.getId( cl );
					// the consumer started, which means the ranged requirement resolved;
					// make sure that was not by looking up exact 2.17.0 only
					var providerCl = variables.service.getClassLoader( "lucee.test.vr.provider", "2.17.1", [ File.init( extra ) ] );
					var providerId = variables.service.getId( providerCl );
					if ( isNull( providerId ) || !findNoCase( "2.17.1", providerId ) ) {
						fail( "A '>=2.17.0' requirement did not resolve the locally available lucee.test.vr.provider 2.17.1 (id: #isNull( providerId ) ? "null" : providerId#). "
							& "loadMissing must not treat bundle-version>=X as the exact version X." );
					}
				}
				catch ( any e ) {
					if ( findNoCase( "must not treat", e.message ) ) rethrow;
					fail( "A '>=2.17.0' requirement did not resolve the locally available lucee.test.vr.provider 2.17.1. "
						& "loadMissing treats bundle-version>=X as the exact version X (it would look for 2.17.0 and ignore 2.17.1). "
						& errorText( e ) );
				}
				finally {
					try { variables.service.uninstall( File.init( consumer ) ); } catch ( any ignore ) {}
					try { variables.service.uninstall( File.init( provider ) ); } catch ( any ignore ) {}
				}
			});

		});
	}

	/**
	 * The availability test must see the untouched startup state. These tests call
	 * setLibraryDirectory only so they can reach the Felix / version bugs; they do
	 * not fix the essentialOnly lib-folder problem.
	 */
	private void function loadServiceFromLibFolder() {
		if ( !variables.osgi.isAvailable() ) {
			try {
				var cfgS = serverConfig();
				var lib = cfgS.getLibraryDirectory();
				var File = createObject( "java", "java.io.File" );
				var libFile = isInstanceOf( lib, "java.io.File" ) ? lib : File.init( lib.toString() );
				variables.osgi.setLibraryDirectory( libFile );
			}
			catch ( any e ) {
				fail( "OSGi service is not active, and setLibraryDirectory could not be called to load it from the lib folder: #errorText( e )#. "
					& "Core 9.0 does not set the lib folder when the config is essentialOnly (ConfigServerImpl.java:1512-1516)." );
			}
		}
		variables.service = variables.engine.getOSGiService();
		if ( !variables.osgi.isAvailable() || findNoCase( "NoOSGiService", variables.service.getClass().getName() ) ) {
			fail( "OSGi service is still not active after setLibraryDirectory (service class is #variables.service.getClass().getName()#). "
				& "The extension was not loaded from the lib folder. Core 9.0 does not set the lib folder when the config is essentialOnly (ConfigServerImpl.java:1512-1516)." );
		}
	}

	private any function serverConfig() {
		var pw = "webweb";
		if ( structKeyExists( server, "SERVERADMINPASSWORD" ) && len( server.SERVERADMINPASSWORD ) ) pw = server.SERVERADMINPASSWORD;
		else if ( structKeyExists( request, "SERVERADMINPASSWORD" ) && len( request.SERVERADMINPASSWORD ) ) pw = request.SERVERADMINPASSWORD;
		return getPageContext().getConfig().getConfigServer( pw );
	}

	private void function assertBundleClassWorks( required any clazz, required string label, required string version ) {
		if ( isNull( arguments.clazz ) ) {
			fail( "The OSGi service did not return a class for #arguments.label# #arguments.version#." );
		}
		var id = variables.service.getId( arguments.clazz );
		var info = variables.service.getInfo( arguments.clazz );
		if ( isNull( id ) ) {
			fail( "The class for #arguments.label# #arguments.version# was not loaded from an OSGi bundle (getId was null). The service may have fallen back to the normal classloader." );
		}
		if ( isNull( info ) || isNull( info[ "state" ] ) || !listFindNoCase( "active,resolved,starting", info[ "state" ] ) ) {
			var state = ( !isNull( info ) && !isNull( info[ "state" ] ) ) ? info[ "state" ] : "unknown";
			fail( "The bundle for #arguments.label# #arguments.version# is not resolved or active (state: #state#, id: #id#)." );
		}
	}

	private string function errorText( required any e ) {
		var type = structKeyExists( arguments.e, "type" ) ? toString( arguments.e.type ) : "";
		var msg = ( structKeyExists( arguments.e, "message" ) && !isNull( arguments.e.message ) ) ? toString( arguments.e.message ) : "";
		var detail = ( structKeyExists( arguments.e, "detail" ) && !isNull( arguments.e.detail ) ) ? toString( arguments.e.detail ) : "";
		var cause = "";
		if ( structKeyExists( arguments.e, "cause" ) && !isNull( arguments.e.cause ) ) {
			if ( isSimpleValue( arguments.e.cause ) ) cause = toString( arguments.e.cause );
			else if ( isStruct( arguments.e.cause ) && structKeyExists( arguments.e.cause, "message" ) ) cause = toString( arguments.e.cause.message );
			else if ( isObject( arguments.e.cause ) ) {
				try { cause = arguments.e.cause.getMessage(); } catch ( any ignore ) {}
				try {
					var nested = arguments.e.cause.getCause();
					if ( !isNull( nested ) && !isNull( nested.getMessage() ) && !find( nested.getMessage(), cause ) ) {
						cause &= " | " & nested.getMessage();
					}
				}
				catch ( any ignore ) {}
			}
		}
		if ( !len( cause ) && structKeyExists( arguments.e, "stacktrace" ) && findNoCase( "Caused by:", arguments.e.stacktrace ) ) {
			cause = trim( mid( arguments.e.stacktrace, findNoCase( "Caused by:", arguments.e.stacktrace ), 400 ) );
		}
		return trim( type & ": " & msg & ( len( detail ) ? " | " & detail : "" ) & ( len( cause ) && cause != msg ? " | " & cause : "" ) );
	}

	private boolean function isPreRelease( required string version ) {
		return refindNoCase( "rc|beta|alpha|snapshot|[-.]m[0-9]", arguments.version ) > 0;
	}

	// true when version is in [from, to), comparing the leading numeric parts
	private boolean function isVersionInHalfOpenRange( required string version, required string from, required string to ) {
		var v = numericVersionPrefix( arguments.version );
		return compareVersionParts( v, numericVersionPrefix( arguments.from ) ) >= 0
			&& compareVersionParts( v, numericVersionPrefix( arguments.to ) ) < 0;
	}

	private array function numericVersionPrefix( required string version ) {
		var parts = [];
		var token = "";
		var i = 0;
		var ch = "";
		for ( i = 1; i <= len( arguments.version ); i++ ) {
			ch = mid( arguments.version, i, 1 );
			if ( ch >= "0" && ch <= "9" ) {
				token &= ch;
			}
			else if ( ch == "." ) {
				arrayAppend( parts, val( token ) );
				token = "";
			}
			else {
				break;
			}
		}
		if ( len( token ) ) arrayAppend( parts, val( token ) );
		return parts;
	}

	private numeric function compareVersionParts( required array left, required array right ) {
		var n = max( arrayLen( arguments.left ), arrayLen( arguments.right ) );
		var i = 0;
		var a = 0;
		var b = 0;
		for ( i = 1; i <= n; i++ ) {
			a = i <= arrayLen( arguments.left ) ? arguments.left[ i ] : 0;
			b = i <= arrayLen( arguments.right ) ? arguments.right[ i ] : 0;
			if ( a > b ) return 1;
			if ( a < b ) return -1;
		}
		return 0;
	}

	private string function createBundleJar( required string dir, required string name, required string version, string extraHeader="" ) {
		var nl = chr( 13 ) & chr( 10 );
		var manifest = "Manifest-Version: 1.0" & nl
			& "Bundle-ManifestVersion: 2" & nl
			& "Bundle-SymbolicName: " & arguments.name & nl
			& "Bundle-Version: " & arguments.version & nl;
		if ( len( arguments.extraHeader ) ) manifest &= arguments.extraHeader & nl;
		manifest &= nl;
		var jar = arguments.dir & arguments.name & "-" & arguments.version & ".jar";
		var bytes = createObject( "java", "java.lang.String" ).init( manifest ).getBytes( "UTF-8" );
		var mf = createObject( "java", "java.util.jar.Manifest" ).init( createObject( "java", "java.io.ByteArrayInputStream" ).init( bytes ) );
		var jos = createObject( "java", "java.util.jar.JarOutputStream" ).init( createObject( "java", "java.io.FileOutputStream" ).init( jar ), mf );
		jos.close();
		return jar;
	}

}
