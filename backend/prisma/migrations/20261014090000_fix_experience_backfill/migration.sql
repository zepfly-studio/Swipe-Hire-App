-- The previous migration's experience pattern had a capture group, and
-- PostgreSQL's substring(... from pattern) returns the group rather than the
-- whole match, so every profile ended up with 0 years. Same intent, fixed
-- pattern (matches backend/src/lib/derive.js: the first number in the text,
-- "Fresher" and anything without a digit are 0).
UPDATE "candidate_profiles" SET
  "experienceYears" = COALESCE(NULLIF(substring("experience" from '[0-9]+\.?[0-9]*'), '')::float, 0);
