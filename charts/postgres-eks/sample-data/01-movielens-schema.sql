-- Movielens sample data schema
-- To be loaded into sample-source-postgres

CREATE TABLE IF NOT EXISTS movies (
    movieid INTEGER PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    genres VARCHAR(500)
);

CREATE TABLE IF NOT EXISTS links (
    movieid INTEGER PRIMARY KEY REFERENCES movies(movieid),
    imdbid INTEGER,
    tmdbid INTEGER
);

CREATE TABLE IF NOT EXISTS ratings (
    userid INTEGER NOT NULL,
    movieid INTEGER NOT NULL REFERENCES movies(movieid),
    rating DECIMAL(2,1) NOT NULL,
    timestamp BIGINT NOT NULL,
    PRIMARY KEY (userid, movieid, timestamp)
);

CREATE TABLE IF NOT EXISTS tags (
    userid INTEGER NOT NULL,
    movieid INTEGER NOT NULL REFERENCES movies(movieid),
    tag VARCHAR(500) NOT NULL,
    timestamp BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_ratings_movieid ON ratings(movieid);
CREATE INDEX IF NOT EXISTS idx_ratings_userid ON ratings(userid);
CREATE INDEX IF NOT EXISTS idx_tags_movieid ON tags(movieid);
CREATE INDEX IF NOT EXISTS idx_tags_userid ON tags(userid);
