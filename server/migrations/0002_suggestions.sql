-- What's missing is now one list of suggestions (kind "wish"), each with links and photos.
-- Inspiration images and reviews are gone, and a suggestion has no status: one the person
-- doesn't want, they delete.

-- Inspiration and reviews go, with the photos and comments that belonged to an inspiration image.
DELETE FROM changes WHERE kind IN ('reference', 'review')
  OR (kind = 'photo' AND json_extract(after_json, '$.data.ownerKind') = 'reference')
  OR (kind = 'comment' AND json_extract(after_json, '$.data.subjectKind') = 'reference');
DELETE FROM docs WHERE kind IN ('reference', 'review')
  OR (kind = 'photo' AND json_extract(data, '$.ownerKind') = 'reference')
  OR (kind = 'comment' AND json_extract(data, '$.subjectKind') = 'reference');

-- A suggestion's one link becomes a list of links, and its status goes: in the record and in its
-- history, so undoing an old change brings back the new shape.
UPDATE docs SET data = json_remove(
    json_set(data, '$.links', json(CASE WHEN json_extract(data, '$.link') IS NULL THEN '[]' ELSE json_array(json_extract(data, '$.link')) END)),
    '$.link', '$.status')
  WHERE kind = 'wish';
UPDATE changes SET after_json = json_remove(
    json_set(after_json, '$.data.links', json(CASE WHEN json_extract(after_json, '$.data.link') IS NULL THEN '[]' ELSE json_array(json_extract(after_json, '$.data.link')) END)),
    '$.data.link', '$.data.status')
  WHERE kind = 'wish';
UPDATE changes SET before_json = json_remove(
    json_set(before_json, '$.data.links', json(CASE WHEN json_extract(before_json, '$.data.link') IS NULL THEN '[]' ELSE json_array(json_extract(before_json, '$.data.link')) END)),
    '$.data.link', '$.data.status')
  WHERE kind = 'wish' AND before_json IS NOT NULL;
