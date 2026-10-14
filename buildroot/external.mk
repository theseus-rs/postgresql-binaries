include $(sort $(wildcard $(BR2_EXTERNAL_POSTGRESQL_BINARIES_PATH)/package/*/*.mk))

# Clang 16 only discovers Python when LLVM tests are enabled, but its module
# export generation also needs it in a standalone build with tests disabled.
ifeq ($(LLVM_PROJECT_VERSION_MAJOR),16)
HOST_CLANG_CONF_OPTS += -DPython3_EXECUTABLE=$(HOST_DIR)/bin/python3
endif
