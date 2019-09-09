# igorzhivilo.com blog

## Installation

- git clone https://github.com/mmistakes/minimal-mistakes.git
- rename cloned directory to 'igorzhivilo'
- Replace _posts, _pages, assets directories with my data
- Update _config.yml 
- Run bundle install
- Run bundle exec jekyll serve

## deployment

- Check you have s3_website directory with 3 files: Dockerfile / build.sh / deploy.sh
- Check s3_website.yml exists in root of 'igorzhivilo' with creds to s3
- Install Docker (if not installed yet)
- sh build.sh # just need to do it once to create the image
- sh deploy.sh # loads info from ../s3_website.yml
