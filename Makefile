# Signed (Personal Team):   make ipa          → build/ios/ipa/CampusApp.ipa
# Unsigned (no codesign):  make ipa-unsigned → build/ios/ipa/CampusApp_unsigned.ipa
# SideStore checklist:      make sidestore-help
.PHONY: ipa ipa-unsigned sidestore-help
ipa:
	@./scripts/build_ipa_campusapp.sh

ipa-unsigned:
	@./scripts/build_ipa_campusapp_unsigned.sh

sidestore-help:
	@cat scripts/SIDESTORE_RELEASE.txt
