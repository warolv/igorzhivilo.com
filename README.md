# igorzhivilo.com blog

## Installation

- git clone https://github.com/mmistakes/minimal-mistakes.git
- rename cloned directory to 'igorzhivilo'
- Replace _posts, _pages, assets directories with my data
- Update _config.yml 
- Run bundle install
- Run bundle exec jekyll serve

## Deployment

- Check you have s3_website directory with 3 files: Dockerfile / build.sh / deploy.sh
- Check s3_website.yml exists in root of 'igorzhivilo' with creds to s3
- Check you have public bucket policy on your s3 bucket/permissions
- Install Docker (if not installed yet)
- sh build.sh # just need to do it once to create the image
- sh deploy.sh # loads info from ../s3_website.yml

## Setting you custom domain with AWS s3 and hover
How to set two buckets in AWS s3, igorzhivilo with content and www.igorzhivilo.com which redirects to igorzhivilo.com
https://docs.aws.amazon.com/AmazonS3/latest/dev/website-hosting-custom-domain-walkthrough.html

## Adding comments to your blog with disqus service and via _config.yml
```
comments:
  provider               : "disqus"
  disqus:
    shortname            : "you_shortname"
``` 
- Add 'div' with id="disqus_thread" to needed layout


## Adding google analytics via _config.yml
```
analytics:
  provider               : "google-gtag"
  google:
    tracking_id          : "UA-xxxxx-x"
    anonymize_ip         : false
```

## Adding seo/keywords
- Add keywords to seo.html
```
description: descr1, descr2, descr3
keywords: 
  - aaa
  - bbb
  - ccc
```

```erb
{%- if page.title -%}
  {%- assign seo_title = page.title | append: " " | append: title_separator | append: " " | append: site.title -%}
{%- endif -%}
```
- Add keywords / description to post

## Adding thumbnail image previes to list of posts
- Add to post
```
---
thumbnail: "/assets/images/jenkins-eks/eks/1.png"
---
```

## Add to archive-single.html
```html
{% if post.thumbnail %}
  <img src="{{ post.thumbnail }}" style="height:280px;display:block;margin:20px auto 0px auto;" />
{% endif %}
```
