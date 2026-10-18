// Direct-only game defaults. Tikkies users keep their own event rules.
export const LIKES_PER_BOOST=20;
export const SOCIAL_MAPPINGS=[
 {sourceType:'like',giftName:'20 Likes / viewer',eventKey:'speed_boost',likeCount:LIKES_PER_BOOST},
 {sourceType:'follow',giftName:'Follow',eventKey:'fly'}
];
export const directMappings=rows=>[...rows,...SOCIAL_MAPPINGS];
