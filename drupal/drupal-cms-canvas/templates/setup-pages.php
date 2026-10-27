<?php

/**
 * @file
 * Example: creates Canvas pages, menu links, header and footer.
 *
 * Copy to scripts/setup-pages.php (with lib/CanvasTree.php beside it in
 * scripts/lib/), change the copy, then run:
 *   ddev drush php:script scripts/setup-pages.php
 * Safe to re-run: pages are matched by URL alias and rebuilt in place, which
 * also discards any edits made to them in Canvas.
 */

require_once __DIR__ . '/lib/CanvasTree.php';

$site_name = 'Example Business';
$contact = '/contact';

$pages = [];

// Home.
$t = new CanvasTree();
$t->hero('What you do, in one line', 'Who it is for and why they should get in touch.', 'Get in touch', $contact);
$what = $t->section('What I do');
$t->cards($what, [
  ['rocket', 'Service one', 'One sentence about it.', '/service-one'],
  ['wrench', 'Service two', 'One sentence about it.', '/service-two'],
  ['lifebuoy', 'Service three', 'One sentence about it.', '/service-three'],
]);
// Needs a view with a block display; see setup-content-type.php.
// $t->viewsBlock('items', 'block_featured', 'Recent work', 3);
$t->cta('Ready to get started?', 'Tell me a little about what you need.', 'Get in touch', $contact);
$pages['/home'] = ['Home', "$site_name: what you do, where.", $t];

// About.
$t = new CanvasTree();
$t->hero('About', 'A short line about you.', 'Get in touch', $contact);
$t->section('Hello', '<p>[A few lines about you.]</p>');
$pages['/about'] = ['About', "About $site_name.", $t];

// Contact: the contact_form webform comes from the drupal_cms_forms recipe.
$t = new CanvasTree();
$t->hero('Get in touch', 'Tell me a little about what you need.', 'About me', '/about');
$form = $t->section(NULL, '<p>Use the form below.</p>');
$t->webform($form, 'contact_form');
$pages['/contact'] = ['Contact', "Contact $site_name.", $t];

$page_ids = canvas_save_pages($pages);

if (isset($page_ids['/home'])) {
  \Drupal::configFactory()->getEditable('system.site')->set('page.front', '/home')->save();
}

$weight = 0;
foreach (['/about' => 'About'] as $alias => $title) {
  if (isset($page_ids[$alias])) {
    canvas_ensure_menu_link('main', $title, 'entity:canvas_page/' . $page_ids[$alias], $weight++);
  }
}
if (isset($page_ids['/contact'])) {
  canvas_ensure_menu_link('footer', 'Contact', 'entity:canvas_page/' . $page_ids['/contact'], 0);
}

canvas_set_header_footer(
  'Get in touch',
  $contact,
  "<p><strong>$site_name</strong><br>One line about the business.</p>",
  '<p>[Phone / email]</p>',
);

// No mail transport on a new server: the email handler would show visitors
// an error. Keep submissions in Drupal only, purged after 180 days, and turn
// the handler back on once SMTP is set up.
$webform = \Drupal::entityTypeManager()->getStorage('webform')->load('contact_form');
if ($webform) {
  $webform->setSetting('purge', 'all');
  $webform->setSetting('purge_days', 180);
  $webform->getHandler('email')->disable();
  $webform->save();
  echo "Contact form: email paused, submissions kept for 180 days.\n";
}
