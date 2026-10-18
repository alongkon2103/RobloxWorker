-- Server-only. One batched HTTP publication per interval for all enabled owners.
return {
 Enabled=true,
 -- Enable only after deploying schema v2 and installing the map-specific server Secret.
 ScopedPublishingEnabled=true,
 MapSecretName="OVERLAY_MAP_API_KEY",
 PublishInterval=1,
 RouteSamples=1024,
 PublicOrigin="https://rbworker.aclassstore.com",
}
