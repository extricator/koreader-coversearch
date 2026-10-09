These small, handcrafted EPUB fixtures exercise native metadata extraction. They
use calibre's identifier representations: EPUB 2 stores a `dc:identifier` with
`opf:scheme="ISBN"`; EPUB 3 stores `isbn:9780441172719` as its identifier text.
Both include a separate package UUID to ensure it doesn't obscure the ISBN.
They contain no cover and aren't intended as rendering or EPUB conformance tests.
