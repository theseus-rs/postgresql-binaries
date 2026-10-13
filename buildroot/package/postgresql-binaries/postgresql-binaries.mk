POSTGRESQL_BINARIES_VERSION = $(PG_PACKAGING_VERSION)
POSTGRESQL_BINARIES_SITE = $(PG_SOURCE_DIRECTORY)
POSTGRESQL_BINARIES_SITE_METHOD = local
POSTGRESQL_BINARIES_LICENSE = PostgreSQL
POSTGRESQL_BINARIES_LICENSE_FILES = COPYRIGHT
POSTGRESQL_BINARIES_DEPENDENCIES = host-bison host-flex host-jq host-pkgconf host-zic \
	icu libxml2 libxslt libkrb5 openssl readline util-linux zlib lz4 zstd
POSTGRESQL_BINARIES_CONF_OPTS = \
	--prefix=/opt/postgresql --exec-prefix=/opt/postgresql \
	--bindir=/opt/postgresql/bin --libdir=/opt/postgresql/lib \
	--includedir=/opt/postgresql/include --datarootdir=/opt/postgresql/share \
	--enable-option-checking=fatal --with-gssapi --with-icu --without-ldap \
	--with-libxml --with-libxslt --with-lz4 --with-openssl \
	--with-pgport=5432 --with-readline --with-uuid=e2fs
# The export-dynamic probe executes a target binary and otherwise assumes "no"
# when cross-compiling; extensions need the backend's exported symbols.
POSTGRESQL_BINARIES_CONF_ENV = \
	CFLAGS="$(TARGET_CFLAGS) -std=gnu17" \
	pgac_cv_prog_cc_LDFLAGS_EX_BE__Wl___export_dynamic=yes \
	XML2_CONFIG=$(STAGING_DIR)/usr/bin/xml2-config \
	KRB5_CONFIG=$(STAGING_DIR)/usr/bin/krb5-config

ifneq ($(filter 14 15 16,$(PG_MAJOR_VERSION)),)
POSTGRESQL_BINARIES_CONF_OPTS += --enable-thread-safety
endif

ifneq ($(PG_MAJOR_VERSION),14)
POSTGRESQL_BINARIES_DEPENDENCIES += python3 host-python3
POSTGRESQL_BINARIES_CONF_OPTS += --with-python
POSTGRESQL_BINARIES_CONF_ENV += PYTHON=$(@D)/cross-python
POSTGRESQL_BINARIES_MAKE_OPTS += world-bin
POSTGRESQL_BINARIES_INSTALL_TARGET_OPTS = DESTDIR=$(TARGET_DIR) install-world-bin

define POSTGRESQL_BINARIES_PREPARE_PYTHON
	$(SED) 's|@HOST_DIR@|$(HOST_DIR)|g; s|@STAGING_DIR@|$(STAGING_DIR)|g; s|@PYTHON_VERSION@|$(PYTHON3_VERSION_MAJOR)|g' $(@D)/cross-python
	if test ! -f $(@D)/.stamp_plpython_relocated; then \
		PATH=$(HOST_DIR)/bin:$(BR_PATH) bash $(BR2_EXTERNAL_POSTGRESQL_BINARIES_PATH)/../scripts/relocate-plpython.sh $(@D) && \
		touch $(@D)/.stamp_plpython_relocated; \
	fi
endef
POSTGRESQL_BINARIES_PRE_CONFIGURE_HOOKS += POSTGRESQL_BINARIES_PREPARE_PYTHON
else
POSTGRESQL_BINARIES_INSTALL_TARGET_OPTS = DESTDIR=$(TARGET_DIR) install
endif

ifneq ($(filter 16 17 18,$(PG_MAJOR_VERSION)),)
POSTGRESQL_BINARIES_CONF_OPTS += --with-zstd
ifeq ($(BR2_PACKAGE_LLVM),y)
POSTGRESQL_BINARIES_DEPENDENCIES += llvm host-clang
POSTGRESQL_BINARIES_CONF_OPTS += --with-llvm
POSTGRESQL_BINARIES_CONF_ENV += LLVM_CONFIG=$(STAGING_DIR)/usr/bin/llvm-config CLANG=$(HOST_DIR)/bin/clang
POSTGRESQL_BINARIES_MAKE_OPTS += LLVM_BINPATH=$(HOST_DIR)/bin
POSTGRESQL_BINARIES_INSTALL_TARGET_OPTS += LLVM_BINPATH=$(HOST_DIR)/bin
endif
endif

define POSTGRESQL_BINARIES_INSTALL_METADATA
	$(TARGET_MAKE_ENV) MAKELEVEL=0 $(MAKE) -C $(@D)/contrib DESTDIR=$(TARGET_DIR) LLVM_BINPATH=$(HOST_DIR)/bin install
	$(INSTALL) -m 0644 $(@D)/COPYRIGHT $(@D)/source-input.json $(TARGET_DIR)/opt/postgresql/
endef
POSTGRESQL_BINARIES_POST_INSTALL_TARGET_HOOKS += POSTGRESQL_BINARIES_INSTALL_METADATA

define POSTGRESQL_BINARIES_CONFIGURE_CMDS
	(cd $(@D); $(TARGET_CONFIGURE_OPTS) $(POSTGRESQL_BINARIES_CONF_ENV) \
		./configure --build=$(GNU_HOST_NAME) --host=$(GNU_TARGET_NAME) \
		$(POSTGRESQL_BINARIES_CONF_OPTS))
endef

define POSTGRESQL_BINARIES_BUILD_CMDS
	# PostgreSQL generates shared headers only at its own top-level make.
	$(TARGET_MAKE_ENV) MAKELEVEL=0 $(MAKE) -C $(@D) ZIC=$(ZIC) $(POSTGRESQL_BINARIES_MAKE_OPTS)
endef

define POSTGRESQL_BINARIES_INSTALL_TARGET_CMDS
	$(TARGET_MAKE_ENV) MAKELEVEL=0 $(MAKE) -C $(@D) ZIC=$(ZIC) $(POSTGRESQL_BINARIES_INSTALL_TARGET_OPTS)
endef

$(eval $(generic-package))
