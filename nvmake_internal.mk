ifeq ($(LOCAL_MODULE_CLASS),SHARED_LIBRARIES)
OVERRIDE_BUILT_MODULE_PATH := $($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_OUT_INTERMEDIATE_LIBRARIES)
endif

NVIDIA_NVMAKE_ADDITIONAL_DEPENDENCIES := \
	$(LOCAL_ADDITIONAL_DEPENDENCIES) \
	$(foreach l,$(LOCAL_SHARED_LIBRARIES),$($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_OUT_INTERMEDIATE_LIBRARIES)/$(l).so) \
	$(foreach l,$(LOCAL_STATIC_LIBRARIES),$(call intermediates-dir-for, \
	  STATIC_LIBRARIES,$(l),,,$(LOCAL_2ND_ARCH_VAR_PREFIX))/$(l).a)

ifeq ($(TARGET_$(LOCAL_2ND_ARCH_VAR_PREFIX)ARCH),arm)
NVIDIA_NVMAKE_TARGET_ABI := _androideabi
NVIDIA_NVMAKE_TARGET_ARCH := ARMv7
else
NVIDIA_NVMAKE_TARGET_ABI :=
NVIDIA_NVMAKE_TARGET_ARCH := aarch64
endif

NVIDIA_NVMAKE_OUTPUT_ROOT := $(abspath $($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_OUT_INTERMEDIATES)/NVMAKE)

NVIDIA_NVMAKE_OUTPUT := \
    $(NVIDIA_NVMAKE_OUTPUT_ROOT)/Android_$(NVIDIA_NVMAKE_TARGET_ARCH)$(NVIDIA_NVMAKE_TARGET_ABI)_$(NVIDIA_NVMAKE_BUILD_TYPE)/$(LOCAL_NVIDIA_NVMAKE_BUILD_DIR)

NVIDIA_NVMAKE_MODULE := \
    $(NVIDIA_NVMAKE_OUTPUT)/$(NVIDIA_NVMAKE_MODULE_PRIVATE_PATH)/$(NVIDIA_NVMAKE_MODULE_NAME)$(LOCAL_MODULE_SUFFIX)


# Android builds set NV_INTERNAL_PROFILE in internal builds, and nothing
# on external builds. Convert this to nvmake convention.
ifeq ($(NV_INTERNAL_PROFILE),1)
NVIDIA_NVMAKE_PROFILE :
else
NVIDIA_NVMAKE_PROFILE := NV_EXTERNAL_PROFILE=1
endif

#
# Bring module from the nvmake build output, and apply the usual
# processing for shared library or executable.
#

include $(BUILD_SYSTEM)/dynamic_binary.mk

my_target_crtbegin_so_o := $($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_CRTBEGIN_SO_O)
my_target_crtend_so_o := $($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_CRTEND_SO_O)

$(linked_module): PRIVATE_TARGET_GLOBAL_LD_DIRS := $($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_GLOBAL_LD_DIRS)
$(linked_module): PRIVATE_TARGET_GLOBAL_LDFLAGS := $($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_GLOBAL_LDFLAGS)
$(linked_module): PRIVATE_TARGET_LIBGCC := $($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_LIBGCC)
$(linked_module): PRIVATE_TARGET_CRTBEGIN_SO_O := $(my_target_crtbegin_so_o)
$(linked_module): PRIVATE_TARGET_CRTEND_SO_O := $(my_target_crtend_so_o)
$(linked_module): NVIDIA_NVMAKE_MODULE := $(NVIDIA_NVMAKE_MODULE)

#
# Call into the nvmake build system to build the module
#
# Add NVUB_SUPPORTS_TXXX=1 to temporarily enable a chip
#

# We'll be limiting this to libcuda once module deliveries happen
#ifeq ($(LOCAL_MODULE),libcuda)
# HACK until the cuda build system uses ANDROID_DSO_LDFLAGS
LOCAL_NVIDIA_NVMAKE_ARGS += \
    TARGET_OUT_INTERMEDIATE_LIBRARIES=$(abspath $($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_OUT_INTERMEDIATE_LIBRARIES)) \
    TARGET_LIBGCC=$($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_LIBGCC)
#endif

$(linked_module): NVIDIA_NVMAKE_COMMON_BUILD_PARAMS := \
    TEGRA_TOP=$(TEGRA_TOP) \
    ANDROID_BUILD_TOP=$(ANDROID_BUILD_TOP) \
    OUT=$(OUT) \
    NV_OUTPUT_ROOT=$(NVIDIA_NVMAKE_OUTPUT_ROOT) \
    NV_SOURCE=$(NVIDIA_NVMAKE_TOP) \
    NV_TOOLS=$(P4ROOT)/sw/tools \
    NV_HOST_OS=Linux \
    NV_HOST_ARCH=x86 \
    NV_TARGET_OS=Android \
    NV_TARGET_ARCH=$(NVIDIA_NVMAKE_TARGET_ARCH) \
    NV_BUILD_TYPE=$(NVIDIA_NVMAKE_BUILD_TYPE) \
    $(NVIDIA_NVMAKE_PROFILE) \
    NV_COVERAGE_ENABLED=$(NVIDIA_COVERAGE_ENABLED) \
    TARGET_TOOLS_PREFIX=$(abspath $($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_TOOLS_PREFIX)) \
    TARGET_C_INCLUDES="$(foreach inc,external/stlport/stlport $($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_C_INCLUDES) bionic,$(abspath $(inc)))" \
    TARGET_GLOBAL_CFLAGS="$($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_GLOBAL_CFLAGS)" \
    $(NVUB_SUPPORTS_FLAG_LIST) \
    $(NVIDIA_NVMAKE_VERBOSE) \
    $(NVIDIA_NVMAKE_GUARDWORD) \
    $(LOCAL_NVIDIA_NVMAKE_ARGS)

# The Aarch64 uses ld instead of gold as a linker. ld doesn't support gc-sections
ifeq ($($(LOCAL_2ND_ARCH_VAR_PREFIX)TARGET_ARCH),arm)
$(linked_module): PRIVATE_EXTRA_LDFLAGS := -Wl,--gc-sections
else
$(linked_module): PRIVATE_EXTRA_LDFLAGS :=
endif

$(linked_module): NVIDIA_NVMAKE_BUILD_PARAMS = \
    $(NVIDIA_NVMAKE_COMMON_BUILD_PARAMS) \
    ANDROID_IMPORT_INCLUDES="$(subst -I ,-I$(abspath $(TOP))/,\
          $(shell cat $(PRIVATE_IMPORT_INCLUDES)))" \
    ANDROID_DSO_LDFLAGS=" \
          -nostdlib \
	  $(PRIVATE_EXTRA_LDFLAGS) \
	  -Wl,-shared,-Bsymbolic \
	  $(patsubst -L%,-L$(abspath $(TOP))/%,$(PRIVATE_TARGET_GLOBAL_LD_DIRS)) \
          $(abspath $(PRIVATE_TARGET_CRTBEGIN_SO_O)) \
	  -Wl,--whole-archive \
	  $(call normalize-abspath-libraries,$(PRIVATE_ALL_WHOLE_STATIC_LIBRARIES)) \
	  -Wl,--no-whole-archive \
          $(call normalize-abspath-libraries,$(PRIVATE_ALL_STATIC_LIBRARIES)) \
	  $(call normalize-abspath-libraries,$(PRIVATE_ALL_SHARED_LIBRARIES)) \
	  $(PRIVATE_TARGET_GLOBAL_LDFLAGS) \
	  $(PRIVATE_LDFLAGS) \
	  $(abspath $(PRIVATE_TARGET_LIBGCC)) \
	  $(abspath $(PRIVATE_TARGET_CRTEND_SO_O))"

ifeq ($(NV_USE_UNIX_BUILD),1)
  $(linked_module): NVIDIA_NVMAKE_COMMAND := \
    $(NVIDIA_NVMAKE_UNIX_BUILD_COMMAND) \
    --newdir $(NVIDIA_NVMAKE_TOP)/$(LOCAL_NVIDIA_NVMAKE_BUILD_DIR) \
    nvmake
else
  $(linked_module): NVIDIA_NVMAKE_COMMAND := \
    $(MAKE) \
    MAKE=$(shell which $(MAKE)) \
    LD_LIBRARY_PATH=$(NVIDIA_NVMAKE_LIBRARY_PATH) \
    NV_UNIX_BUILD_CHROOT=$(P4ROOT)/sw/tools/unix/hosts/Linux-x86/unix-build \
    -C $(NVIDIA_NVMAKE_TOP)/$(LOCAL_NVIDIA_NVMAKE_BUILD_DIR) \
    -f makefile.nvmk
endif

# This target needs to be forced, nvmake will do its own dependency checking
$(linked_module): $(intermediates)/import_includes $(NVIDIA_NVMAKE_ADDITIONAL_DEPENDENCIES) $(my_target_crtbegin_so_o) $(my_target_crtend_so_o) FORCE | $(ACP)
	@echo "Build with nvmake: $(PRIVATE_MODULE) ($@)"
	@echo "PRIVATE_TARGET_GLOBAL_LD_DIRS: ($(PRIVATE_TARGET_GLOBAL_LD_DIRS))"
	+$(hide) $(NVIDIA_NVMAKE_COMMAND) $(NVIDIA_NVMAKE_BUILD_PARAMS) MAKEFLAGS="$(MAKEFLAGS)"
	@mkdir -p $(dir $@)
	$(hide) $(ACP) -fp $(NVIDIA_NVMAKE_MODULE) $@

#
# Make the module's clean target clean the output directory
#

$(cleantarget) : PRIVATE_NVMAKE_OUTPUT := $(NVIDIA_NVMAKE_OUTPUT)
$(cleantarget)::
	$(hide) rm -r $(PRIVATE_NVMAKE_OUTPUT)

NVIDIA_NVMAKE_OUTPUT :=
NVIDIA_NVMAKE_OUTPUT_ROOT :=
NVIDIA_NVMAKE_MODULE :=
NVIDIA_NVMAKE_TARGET_ABI :=
NVIDIA_NVMAKE_TARGET_ARCH :=
NVIDIA_NVMAKE_ADDITIONAL_DEPENDENCIES :=
NVIDIA_NVMAKE_PROFILE :=
