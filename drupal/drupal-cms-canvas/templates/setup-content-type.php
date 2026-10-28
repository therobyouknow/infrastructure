<?php

/**
 * @file
 * Example: a content type, a tagging vocabulary and a view of card blocks.
 *
 * Generalised from a testimonials script (card-only content) and a projects
 * script (with their own pages). Copy to scripts/, change the settings below,
 * then:
 *   ddev drush php:script scripts/setup-content-type.php
 * Safe to re-run: existing config is left alone.
 *
 * The view gets an "All" block, a "Featured" block and one block per term,
 * named block_<term machine name>. Place them on Canvas pages with
 * CanvasTree::viewsBlock('<view id>', 'block_all', 'Heading', 24).
 */

use Drupal\field\Entity\FieldConfig;
use Drupal\field\Entity\FieldStorageConfig;
use Drupal\node\Entity\NodeType;
use Drupal\pathauto\Entity\PathautoPattern;
use Drupal\taxonomy\Entity\Term;
use Drupal\taxonomy\Entity\Vocabulary;
use Drupal\views\Entity\View;

// --- Settings ---------------------------------------------------------------

$bundle = 'item';
$label = 'Item';
$description = 'Something shown as a card on the site.';
// Own page at /<path>/<title>, or FALSE for card-only content (its URL 404s).
$path = 'items';
$vocabulary = ['vid' => 'category', 'name' => 'Category', 'field' => 'field_category'];
$terms = ['First category', 'Second category'];
$view_id = 'items';
$block_category = 'Site name';

// Field name => settings. Existing storages (e.g. field_description,
// field_content and field_featured_image from Drupal CMS) are reused.
$fields = [
  'field_description' => [
    'type' => 'string_long',
    'label' => 'Summary',
    'description' => 'One or two sentences, shown on cards.',
    'required' => TRUE,
    'widget' => 'string_textarea',
    'formatter' => 'basic_string',
  ],
  $vocabulary['field'] => [
    'type' => 'entity_reference',
    'label' => $vocabulary['name'],
    'cardinality' => -1,
    'storage_settings' => ['target_type' => 'taxonomy_term'],
    'settings' => [
      'handler' => 'default:taxonomy_term',
      'handler_settings' => ['target_bundles' => [$vocabulary['vid'] => $vocabulary['vid']]],
    ],
    'widget' => 'options_buttons',
    'formatter' => 'entity_reference_label',
    'formatter_settings' => ['link' => FALSE],
    'formatter_label' => 'inline',
  ],
  'field_content' => [
    'type' => 'text_long',
    'label' => 'Body',
    'settings' => ['allowed_formats' => ['content_format']],
    'widget' => 'text_textarea',
    'formatter' => 'text_default',
  ],
  'field_featured_image' => [
    'type' => 'entity_reference',
    'label' => 'Image',
    'storage_settings' => ['target_type' => 'media'],
    'settings' => [
      'handler' => 'default:media',
      'handler_settings' => ['target_bundles' => ['image' => 'image']],
    ],
    'widget' => 'media_library_widget',
    'formatter' => 'entity_reference_entity_view',
    'formatter_settings' => ['view_mode' => '16_9_large'],
  ],
  'field_link' => [
    'type' => 'link',
    'label' => 'Link',
    'settings' => ['link_type' => 16, 'title' => 0],
    'widget' => 'link_default',
    'formatter' => 'link',
    'formatter_settings' => ['rel' => 'noopener', 'target' => '_blank'],
    'formatter_label' => 'inline',
  ],
  'field_featured' => [
    'type' => 'boolean',
    'label' => 'Feature on the home page',
    'widget' => 'boolean_checkbox',
    'widget_settings' => ['display_label' => TRUE],
    'formatter' => NULL,
  ],
];

// --- Content type and vocabulary ---------------------------------------------

\Drupal::service('module_installer')->install(['link']);

if (!Vocabulary::load($vocabulary['vid'])) {
  Vocabulary::create(['vid' => $vocabulary['vid'], 'name' => $vocabulary['name']])->save();
  foreach ($terms as $weight => $name) {
    Term::create(['vid' => $vocabulary['vid'], 'name' => $name, 'weight' => $weight])->save();
  }
}

if (!NodeType::load($bundle)) {
  NodeType::create([
    'type' => $bundle,
    'name' => $label,
    'description' => $description,
    'new_revision' => TRUE,
    'display_submitted' => FALSE,
    'preview_mode' => 1,
  ])->save();
}

$repository = \Drupal::service('entity_display.repository');
$form_display = $repository->getFormDisplay('node', $bundle);
$view_display = $repository->getViewDisplay('node', $bundle);
$weight = 0;

foreach ($fields as $name => $info) {
  if (!FieldStorageConfig::loadByName('node', $name)) {
    FieldStorageConfig::create([
      'field_name' => $name,
      'entity_type' => 'node',
      'type' => $info['type'],
      'cardinality' => $info['cardinality'] ?? 1,
      'settings' => $info['storage_settings'] ?? [],
    ])->save();
    // FieldConfig::create() checks the cached storage definitions.
    \Drupal::service('entity_field.manager')->clearCachedFieldDefinitions();
  }
  if (!FieldConfig::loadByName('node', $bundle, $name)) {
    FieldConfig::create([
      'field_name' => $name,
      'entity_type' => 'node',
      'bundle' => $bundle,
      'label' => $info['label'],
      'description' => $info['description'] ?? '',
      'required' => $info['required'] ?? FALSE,
      'settings' => $info['settings'] ?? [],
    ])->save();
  }
  $form_display->setComponent($name, [
    'type' => $info['widget'],
    'weight' => ++$weight,
    'settings' => $info['widget_settings'] ?? [],
  ]);
  if ($info['formatter']) {
    $view_display->setComponent($name, [
      'type' => $info['formatter'],
      'label' => $info['formatter_label'] ?? 'hidden',
      'weight' => $weight,
      'settings' => $info['formatter_settings'] ?? [],
    ]);
  }
  else {
    $view_display->removeComponent($name);
  }
}
$form_display->save();
foreach (['links', 'uid', 'created', 'content_moderation_control'] as $name) {
  $view_display->removeComponent($name);
}
$view_display->save();

if ($path && !PathautoPattern::load($bundle)) {
  $pattern = PathautoPattern::create([
    'id' => $bundle,
    'label' => $label,
    'type' => 'canonical_entities:node',
    'pattern' => "$path/[node:title]",
    'weight' => -5,
  ]);
  $pattern->addSelectionCondition([
    'id' => 'entity_bundle:node',
    'bundles' => [$bundle => $bundle],
    'negate' => FALSE,
    'context_mapping' => ['node' => 'node'],
  ]);
  $pattern->save();
}
elseif (!$path) {
  \Drupal::service('rabbit_hole.behavior_settings_manager')->saveBehaviorSettings([
    'action' => 'page_not_found',
    'allow_override' => 0,
    'redirect' => '',
    'redirect_code' => 301,
    'redirect_fallback_action' => 'bypass',
  ], 'node_type', $bundle);
}

// --- View ------------------------------------------------------------------

if (!View::load($view_id)) {
  $tag_field = $vocabulary['field'];
  $base_filters = [
    'status' => [
      'id' => 'status', 'table' => 'node_field_data', 'field' => 'status',
      'entity_type' => 'node', 'entity_field' => 'status', 'plugin_id' => 'boolean',
      'value' => '1', 'group' => 1, 'expose' => ['operator' => FALSE],
    ],
    'type' => [
      'id' => 'type', 'table' => 'node_field_data', 'field' => 'type',
      'entity_type' => 'node', 'entity_field' => 'type', 'plugin_id' => 'bundle',
      'value' => [$bundle => $bundle], 'group' => 1,
    ],
  ];
  $block = fn (string $title, array $filters, int $items) => [
    'display_plugin' => 'block',
    'display_title' => $title,
    'display_options' => [
      'block_description' => "$label: $title",
      'block_category' => $block_category,
      'defaults' => ['filters' => FALSE, 'filter_groups' => FALSE, 'pager' => FALSE],
      'filters' => $base_filters + $filters,
      'filter_groups' => ['operator' => 'AND', 'groups' => [1 => 'AND']],
      'pager' => ['type' => 'some', 'options' => ['items_per_page' => $items, 'offset' => 0]],
    ],
  ];
  $field = fn (string $name, array $extra = []) => $extra + [
    'id' => $name, 'table' => "node__$name", 'field' => $name,
    'entity_type' => 'node', 'entity_field' => $name, 'plugin_id' => 'field',
    'label' => '', 'element_label_colon' => FALSE,
  ];

  $displays = [
    'default' => [
      'display_plugin' => 'default',
      'id' => 'default',
      'display_title' => 'Default',
      'position' => 0,
      'display_options' => [
        'access' => ['type' => 'perm', 'options' => ['perm' => 'access content']],
        'cache' => ['type' => 'tag'],
        'query' => ['type' => 'views_query'],
        'style' => [
          'type' => 'grid_responsive',
          'options' => ['columns' => 3, 'cell_min_width' => 260, 'grid_gutter' => 24, 'alignment' => 'horizontal'],
        ],
        'row' => ['type' => 'fields', 'options' => []],
        'fields' => [
          'title' => [
            'id' => 'title', 'table' => 'node_field_data', 'field' => 'title',
            'entity_type' => 'node', 'entity_field' => 'title', 'plugin_id' => 'field',
            'label' => '', 'element_label_colon' => FALSE, 'element_type' => 'h3',
            'settings' => ['link_to_entity' => (bool) $path],
          ],
          'field_description' => $field('field_description'),
          $tag_field => $field($tag_field, [
            'type' => 'entity_reference_label',
            'settings' => ['link' => FALSE],
            'group_column' => 'target_id',
            'delta_limit' => 0,
            'multi_type' => 'separator',
            'separator' => ' · ',
            'element_type' => 'small',
          ]),
        ],
        'filters' => $base_filters,
        'filter_groups' => ['operator' => 'AND', 'groups' => [1 => 'AND']],
        'sorts' => [
          'sticky' => [
            'id' => 'sticky', 'table' => 'node_field_data', 'field' => 'sticky',
            'entity_type' => 'node', 'entity_field' => 'sticky', 'plugin_id' => 'boolean',
            'order' => 'DESC',
          ],
          'changed' => [
            'id' => 'changed', 'table' => 'node_field_data', 'field' => 'changed',
            'entity_type' => 'node', 'entity_field' => 'changed', 'plugin_id' => 'date',
            'order' => 'DESC', 'granularity' => 'second',
          ],
        ],
        'pager' => ['type' => 'none', 'options' => ['offset' => 0]],
        'empty' => [
          'area_text_custom' => [
            'id' => 'area_text_custom', 'table' => 'views', 'field' => 'area_text_custom',
            'plugin_id' => 'text_custom', 'empty' => TRUE,
            'content' => 'Coming soon.',
          ],
        ],
      ],
    ],
    'block_all' => ['id' => 'block_all', 'position' => 1] + $block('All', [], 0),
    'block_featured' => ['id' => 'block_featured', 'position' => 2] + $block('Featured', [
      'field_featured_value' => [
        'id' => 'field_featured_value', 'table' => 'node__field_featured',
        'field' => 'field_featured_value', 'plugin_id' => 'boolean',
        'value' => '1', 'group' => 1,
      ],
    ], 3),
  ];

  $position = 3;
  $term_storage = \Drupal::entityTypeManager()->getStorage('taxonomy_term');
  foreach ($term_storage->loadByProperties(['vid' => $vocabulary['vid']]) as $term) {
    $tid = (int) $term->id();
    $id = 'block_' . preg_replace('/[^a-z0-9]+/', '_', strtolower($term->label()));
    $displays[$id] = ['id' => $id, 'position' => $position++] + $block($term->label(), [
      "{$tag_field}_target_id" => [
        'id' => "{$tag_field}_target_id", 'table' => "node__$tag_field",
        'field' => "{$tag_field}_target_id", 'plugin_id' => 'taxonomy_index_tid',
        'value' => [$tid => $tid], 'vid' => $vocabulary['vid'], 'type' => 'select',
        'operator' => 'or', 'group' => 1, 'reduce_duplicates' => TRUE,
      ],
    ], 6);
    echo "View block: $id\n";
  }

  View::create([
    'id' => $view_id,
    'label' => "{$label}s",
    'module' => 'views',
    'description' => "$label cards, shown in blocks on Canvas pages.",
    'base_table' => 'node_field_data',
    'base_field' => 'nid',
    'display' => $displays,
  ])->save();
}

echo "$label setup done.\n";
