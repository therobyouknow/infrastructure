<?php

/**
 * @file
 * Helpers for building Drupal CMS pages with Canvas and the Mercury theme
 * from a Drush script.
 *
 * Copy this file into a project as scripts/lib/CanvasTree.php and load it
 * from a page script run with `ddev drush php:script scripts/setup-pages.php`:
 *
 *   require_once __DIR__ . '/lib/CanvasTree.php';
 *
 * Tested with Drupal CMS 2.2 (Drupal 11.4, Canvas 1.x, Mercury 1.x).
 */

use Drupal\Component\Uuid\Php as Uuid;
use Drupal\menu_link_content\Entity\MenuLinkContent;

/**
 * Builds a flat Canvas component tree.
 *
 * Canvas stores a page as a flat list of components, each pointing at its
 * parent and the parent's slot. add() returns the new component's UUID so
 * children can be attached to it.
 */
final class CanvasTree {

  public array $items = [];

  private Uuid $uuid;

  public function __construct() {
    $this->uuid = new Uuid();
  }

  /**
   * Adds a component, e.g. 'sdc.mercury.text' or 'block.webform_block'.
   */
  public function add(string $component_id, array $inputs = [], ?string $parent = NULL, ?string $slot = NULL): string {
    $component = \Drupal::entityTypeManager()->getStorage('component')->load($component_id);
    if (!$component) {
      throw new \InvalidArgumentException("Unknown Canvas component $component_id");
    }
    // Canvas expects every SDC prop that has a default to be present.
    $props = $component->getSettings()['prop_field_definitions'] ?? [];
    foreach ($props as $name => $definition) {
      $default = $definition['default_value'][0] ?? NULL;
      if (!array_key_exists($name, $inputs) && is_array($default) && count($default) === 1 && isset($default['value'])) {
        $inputs[$name] = $default['value'];
      }
    }
    $id = $this->uuid->generate();
    $this->items[$id] = array_filter([
      'uuid' => $id,
      'component_id' => $component_id,
      'component_version' => $component->getActiveVersion(),
      'parent_uuid' => $parent,
      'slot' => $slot,
      'inputs' => $inputs,
    ], fn ($v) => $v !== NULL);
    return $id;
  }

  /**
   * Full-width coloured banner with an H1 and one button.
   */
  public function hero(string $heading, string $text, string $label, string $href): string {
    return $this->cta($heading, $text, $label, $href, 1, 'primary', '20%');
  }

  /**
   * Call-to-action band; used for both the hero (level 1) and closing CTAs.
   */
  public function cta(string $heading, string $text, string $label, string $href, int $level = 2, string $background = 'secondary', string $overlay = '0%'): string {
    $cta = $this->add('sdc.mercury.cta', [
      'heading_text' => $heading,
      'level' => $level,
      'text' => $text,
      'text_align' => 'center',
      'background_color' => $background,
      'overlay_opacity' => $overlay,
    ]);
    $this->button($label, $href, $cta, 'actions');
    return $cta;
  }

  public function button(string $label, string $href, string $parent, string $slot, string $variant = 'primary', string $size = 'large'): string {
    return $this->add('sdc.mercury.button', [
      'variant' => $variant,
      'size' => $size,
      'label' => $label,
      'href' => $href,
      'icon' => 'arrow-right',
    ], $parent, $slot);
  }

  /**
   * Content section with an optional H2 and rich text.
   *
   * Returns the section UUID; add more components to its 'main_slot'.
   * $background is a Mercury colour name such as 'muted', or '' for none.
   */
  public function section(?string $heading, ?string $html = NULL, string $background = ''): string {
    $section = $this->add('sdc.mercury.section', array_filter([
      'width' => '80%',
      'columns' => '100',
      'margin_block_start' => '48',
      'margin_block_end' => '48',
      'padding_block_start' => $background ? '32' : '0',
      'padding_block_end' => $background ? '32' : '0',
      'background_color' => $background ?: NULL,
    ], fn ($v) => $v !== NULL));
    if ($heading) {
      $this->add('sdc.mercury.heading', ['heading_text' => $heading, 'level' => 2, 'align' => 'left'], $section, 'main_slot');
    }
    if ($html) {
      $this->add('sdc.mercury.text', ['text' => $html, 'text_size' => 'text-lg'], $section, 'main_slot');
    }
    return $section;
  }

  /**
   * Grid of icon cards. $cards is a list of [icon, title, description, url].
   *
   * Icons are Phosphor names (https://phosphoricons.com), e.g. 'drop', 'plant'.
   */
  public function cards(string $parent, array $cards, int $columns = 3): string {
    $grid = $this->add('sdc.mercury.grid', ['width' => '100%', 'columns' => "$columns columns", 'mobile_columns' => '1'], $parent, 'main_slot');
    foreach ($cards as [$icon, $title, $description, $url]) {
      $this->add('sdc.mercury.card-icon', [
        'icon' => $icon,
        'text' => $title,
        'description' => $description,
        'url' => $url,
        'background_color' => 'muted',
        'text_align' => 'left',
      ], $grid, 'main_slot');
    }
    return $grid;
  }

  /**
   * Section containing a Views block display.
   *
   * $items must be 1 or more: Canvas rejects 0 ("show all").
   */
  public function viewsBlock(string $view, string $display, string $heading, int $items, string $background = 'muted'): string {
    $section = $this->section($heading, NULL, $background);
    $this->add("block.views_block.$view-$display", [
      'label' => $heading,
      'label_display' => '0',
      'views_label' => '',
      'items_per_page' => $items,
    ], $section, 'main_slot');
    return $section;
  }

  /**
   * Webform embedded in a section, e.g. the drupal_cms_forms 'contact_form'.
   */
  public function webform(string $parent, string $webform_id = 'contact_form'): string {
    return $this->add('block.webform_block', [
      'label' => 'Contact form',
      'label_display' => '0',
      'webform_id' => $webform_id,
      'default_data' => '',
      'redirect' => FALSE,
      'lazy' => FALSE,
    ], $parent, 'main_slot');
  }

}

/**
 * Creates or rebuilds Canvas pages, matched by URL alias.
 *
 * @param array $pages
 *   Keyed by alias ('/about'): [title, meta description, CanvasTree].
 *
 * @return array
 *   Canvas page IDs keyed by alias, for pages that saved.
 */
function canvas_save_pages(array $pages): array {
  $page_storage = \Drupal::entityTypeManager()->getStorage('canvas_page');
  $alias_manager = \Drupal::service('path_alias.manager');
  $page_ids = [];
  foreach ($pages as $alias => [$title, $description, $tree]) {
    $path = $alias_manager->getPathByAlias($alias);
    $existing = preg_match('#^/page/(\d+)$#', $path, $m) ? $page_storage->load($m[1]) : NULL;
    $page = $existing ?? $page_storage->create(['path' => ['alias' => $alias, 'pathauto' => 0]]);
    $page->set('title', $title);
    $page->set('description', $description);
    $page->set('status', TRUE);
    $page->set('components', array_values($tree->items));
    $violations = $page->validate();
    if ($violations->count()) {
      foreach ($violations as $v) {
        echo "$alias: {$v->getPropertyPath()}: {$v->getMessage()}\n";
      }
      continue;
    }
    $page->save();
    $page_ids[$alias] = $page->id();
    echo ($existing ? 'Updated' : 'Created') . " $title ($alias)\n";
  }
  return $page_ids;
}

/**
 * Adds a menu link, or updates the one with the same title in that menu.
 *
 * Link a Canvas page with 'entity:canvas_page/<id>'.
 */
function canvas_ensure_menu_link(string $menu, string $title, string $uri, int $weight, array $options = []): void {
  $storage = \Drupal::entityTypeManager()->getStorage('menu_link_content');
  $links = $storage->loadByProperties(['menu_name' => $menu, 'title' => $title]);
  $link = reset($links) ?: MenuLinkContent::create(['menu_name' => $menu, 'title' => $title]);
  $link->set('link', ['uri' => $uri, 'options' => $options]);
  $link->set('weight', $weight);
  $link->set('expanded', FALSE);
  $link->save();
}

/**
 * Fills Mercury's header and footer, which live in the theme's page variant.
 *
 * Adds a button beside the main menu and two text blocks to the footer, and
 * shows the site name instead of the logo. Safe to re-run: the slots it
 * fills are cleared first.
 */
function canvas_set_header_footer(string $button_label, string $button_href, string $footer_first_html, string $footer_last_html): void {
  $variant = \Drupal::entityTypeManager()->getStorage('page_variant')->load('theme_mercury');
  $tree = $variant->get('component_tree');
  $navbar = $footer = NULL;
  foreach ($tree as $id => $item) {
    if ($item['component_id'] === 'sdc.mercury.navbar') {
      $navbar = $id;
    }
    if ($item['component_id'] === 'sdc.mercury.footer') {
      $footer = $id;
    }
    if ($item['component_id'] === 'block.system_branding_block') {
      // Show the name until there is a logo.
      $tree[$id]['inputs']['use_site_name'] = TRUE;
      $tree[$id]['inputs']['use_site_logo'] = FALSE;
    }
  }
  $tree = array_filter($tree, fn ($item) => !(
    (($item['parent_uuid'] ?? NULL) === $navbar && $item['slot'] === 'links')
    || (($item['parent_uuid'] ?? NULL) === $footer && in_array($item['slot'], ['footer_first', 'footer_last'], TRUE))
  ));
  $extra = new CanvasTree();
  $extra->button($button_label, $button_href, $navbar, 'links', 'primary', 'medium');
  $extra->add('sdc.mercury.text', ['text' => $footer_first_html, 'text_size' => 'normal'], $footer, 'footer_first');
  $extra->add('sdc.mercury.text', ['text' => $footer_last_html, 'text_size' => 'normal'], $footer, 'footer_last');
  $tree += $extra->items;
  $variant->set('component_tree', $tree);
  $violations = $variant->getTypedData()->validate();
  foreach ($violations as $v) {
    echo "page variant: {$v->getPropertyPath()}: {$v->getMessage()}\n";
  }
  if (!$violations->count()) {
    $variant->save();
    echo "Updated header and footer.\n";
  }
}
