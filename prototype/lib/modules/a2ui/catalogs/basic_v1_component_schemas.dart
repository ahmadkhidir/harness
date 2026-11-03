/// Machine-readable JSON Schemas for the `basic/v1` A2UI component catalog.
///
/// Mirrors the human-readable catalog documentation so surface validation is
/// schema-driven rather than hand-written per component. Only hierarchy-critical
/// fields are `required`; optional presentation fields keep the renderer's
/// defaults for sparse model output.
const Map<String, Map<String, dynamic>> kBasicV1ComponentSchemas = {
  'Text': {
    'type': 'object',
    'properties': {
      'text': {
        'type': ['string', 'number', 'object'],
      },
      'variant': {
        'enum': ['headline', 'title', 'body', 'caption', 'label'],
      },
      // Legacy alias accepted by earlier payloads.
      'style': {
        'enum': ['headline', 'title', 'body', 'caption', 'label'],
      },
      'fontWeight': {
        'enum': ['normal', 'medium', 'bold', 'w600'],
      },
      'color': {'type': 'string'},
      'alignment': {'type': 'string'},
    },
    'additionalProperties': false,
  },
  'Image': {
    'type': 'object',
    'properties': {
      'url': {
        'type': ['string', 'object'],
      },
      'description': {'type': 'string'},
      'fit': {
        'enum': ['cover', 'contain', 'fill', 'none'],
      },
      'aspectRatio': {'type': 'number'},
    },
    'additionalProperties': false,
  },
  'Icon': {
    'type': 'object',
    'properties': {
      'icon': {'type': 'string'},
      'color': {'type': 'string'},
      'size': {'type': 'number'},
    },
    'additionalProperties': false,
  },
  'Video': {
    'type': 'object',
    'properties': {
      'url': {
        'type': ['string', 'object'],
      },
      'autoPlay': {'type': 'boolean'},
      'controls': {'type': 'boolean'},
      'aspectRatio': {'type': 'number'},
    },
    'additionalProperties': false,
  },
  'AudioPlayer': {
    'type': 'object',
    'properties': {
      'url': {
        'type': ['string', 'object'],
      },
      'title': {'type': 'string'},
      'autoPlay': {'type': 'boolean'},
    },
    'additionalProperties': false,
  },
  'Row': {
    'type': 'object',
    'properties': {
      'children': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'spacing': {'type': 'number'},
      'alignment': {
        'enum': ['start', 'center', 'end', 'spaceBetween'],
      },
      'crossAxisAlignment': {'type': 'string'},
      'mainAxisAlignment': {'type': 'string'},
    },
    'required': ['children'],
    'additionalProperties': false,
  },
  'Column': {
    'type': 'object',
    'properties': {
      'children': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'spacing': {'type': 'number'},
      'alignment': {
        'enum': ['start', 'center', 'end', 'stretch'],
      },
      'crossAxisAlignment': {'type': 'string'},
      'mainAxisAlignment': {'type': 'string'},
    },
    'required': ['children'],
    'additionalProperties': false,
  },
  'List': {
    'type': 'object',
    'properties': {
      'children': {
        'type': ['array', 'object'],
      },
      'direction': {
        'enum': ['vertical', 'horizontal'],
      },
      'spacing': {'type': 'number'},
    },
    'required': ['children'],
    'additionalProperties': false,
  },
  'Card': {
    'type': 'object',
    'properties': {
      'child': {'type': 'string'},
      'elevation': {'type': 'number'},
      'padding': {'type': 'number'},
    },
    'required': ['child'],
    'additionalProperties': false,
  },
  'Tabs': {
    'type': 'object',
    'properties': {
      'tabs': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'label': {'type': 'string'},
            'child': {'type': 'string'},
          },
          'required': ['label', 'child'],
          'additionalProperties': false,
        },
      },
    },
    'required': ['tabs'],
    'additionalProperties': false,
  },
  'Modal': {
    'type': 'object',
    'properties': {
      'trigger': {'type': 'string'},
      'content': {'type': 'string'},
      'title': {'type': 'string'},
    },
    'required': ['trigger', 'content'],
    'additionalProperties': false,
  },
  'Divider': {
    'type': 'object',
    'properties': {
      'thickness': {'type': 'number'},
      'color': {'type': 'string'},
    },
    'additionalProperties': false,
  },
  'Button': {
    'type': 'object',
    'properties': {
      'label': {
        'type': ['string', 'number', 'object'],
      },
      'action': {'type': 'string'},
      'style': {
        'enum': ['filled', 'outlined', 'text'],
      },
      'icon': {'type': 'string'},
      'disabled': {'type': 'boolean'},
      'parameters': {'type': 'object'},
      'payload': {'type': 'object'},
    },
    'additionalProperties': false,
  },
  'TextField': {
    'type': 'object',
    'properties': {
      'label': {'type': 'string'},
      'placeholder': {'type': 'string'},
      'value': {
        'type': ['string', 'number', 'boolean', 'object'],
      },
      'variant': {
        'enum': ['text', 'number', 'password', 'multiline'],
      },
      'onChange': {'type': 'string'},
    },
    'additionalProperties': false,
  },
  'CheckBox': {
    'type': 'object',
    'properties': {
      'label': {'type': 'string'},
      'value': {
        'type': ['boolean', 'object'],
      },
      'onChange': {'type': 'string'},
    },
    'additionalProperties': false,
  },
  'ChoicePicker': {
    'type': 'object',
    'properties': {
      'label': {'type': 'string'},
      'options': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'label': {'type': 'string'},
            'value': {'type': 'string'},
          },
          'required': ['label', 'value'],
          'additionalProperties': false,
        },
      },
      'value': {
        'type': ['string', 'object'],
      },
      'onChange': {'type': 'string'},
    },
    'required': ['options'],
    'additionalProperties': false,
  },
  'Slider': {
    'type': 'object',
    'properties': {
      'label': {'type': 'string'},
      'value': {
        'type': ['number', 'object'],
      },
      'min': {'type': 'number'},
      'max': {'type': 'number'},
      'step': {'type': 'number'},
    },
    'additionalProperties': false,
  },
  'DateTimeInput': {
    'type': 'object',
    'properties': {
      'label': {'type': 'string'},
      'variant': {
        'enum': ['date', 'time', 'datetime'],
      },
      'value': {'type': 'string'},
    },
    'additionalProperties': false,
  },
};
