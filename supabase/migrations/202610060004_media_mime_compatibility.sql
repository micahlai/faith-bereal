update storage.buckets
set allowed_mime_types = array[
  'video/quicktime', 'video/mp4', 'image/jpeg',
  'audio/x-caf', 'audio/mp4', 'audio/mpeg', 'audio/wav',
  'application/octet-stream'
]
where id = 'blessing-media';
