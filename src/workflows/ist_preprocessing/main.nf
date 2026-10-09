workflow auto {
  findStates(params, meta.config)
    | meta.workflow.run(
      auto: [publish: "state"]
    )
}

workflow run_wf {
  take:
  input_ch

  main:

  // Default method per step: the default pipeline of the task_ist_preprocessing benchmark.
  // Keep in sync with configs/default_methods.yaml.
  def DEFAULT_METHODS = [
    segmentation:               "custom_segmentation",
    transcript_assignment:      "basic_transcript_assignment",
    count_aggregation:          "basic_count_aggregation",
    qc_filtering:               "basic_qc_filter",
    volume_calculation:         "alpha_shapes",
    normalization:              "normalize_by_volume",
    celltype_annotation:        "tacco",
    expression_correction:      "no_correction",
    gene_efficiency_correction: "no_correction"
  ]

  /****************************************
   *        METHODS AVAILABLE PER STEP    *
   ****************************************/
  segm_methods = [
    custom_segmentation.run(
      args: [labels_key: "cell_labels"]
    ),
    cellpose,
    cellposev4,
    binning,
    stardist,
    watershed
  ]
  ass_methods = [
    basic_transcript_assignment.run(
      args: [
        transcripts_key: "transcripts",
        coordinate_system: "global"
      ]
    ),
    baysor,
    clustermap,
    pciseq,
    comseg,
    proseg,
    segger,
    fastreseg
  ]
  count_aggr_methods = [basic_count_aggregation]
  qc_filter_methods = [basic_qc_filter]
  cell_vol_methods = [alpha_shapes]
  // normalize_by_volume needs the cell volumes, the others normalize the counts directly
  vol_norm_methods = [normalize_by_volume]
  direct_norm_methods = [normalize_by_counts, spanorm]
  cta_methods = [ssam, tacco, moscot, mapmycells, tangram, singler, rctd]
  expr_corr_methods = [no_correction, resolvi_correction, split]
  gene_eff_methods = [gene_eff_no_correction, gene_efficiency_correction]

  def available = [
    segmentation:               segm_methods,
    transcript_assignment:      ass_methods,
    count_aggregation:          count_aggr_methods,
    qc_filtering:               qc_filter_methods,
    volume_calculation:         cell_vol_methods,
    normalization:              vol_norm_methods + direct_norm_methods,
    celltype_annotation:        cta_methods,
    expression_correction:      expr_corr_methods,
    gene_efficiency_correction: gene_eff_methods
  ].collectEntries { step, comps -> [(step): comps.collect { it.config.name }] }

  /****************************************
   *     READ AND VALIDATE USER CONFIG    *
   ****************************************/
  init_ch = input_ch
    | map { id, state ->
      def user_cfg = state.methods_config ? readYaml(state.methods_config) : [:]
      if (user_cfg == null) user_cfg = [:]
      if (!(user_cfg instanceof Map)) {
        throw new IllegalArgumentException("[$id] methods_config must be a mapping of step -> {method, args}")
      }

      // Fail on unknown steps, so a typo does not silently fall back to the default
      def unknown_steps = user_cfg.keySet() - DEFAULT_METHODS.keySet()
      if (unknown_steps) {
        throw new IllegalArgumentException(
          "[$id] Unknown step(s) in methods_config: ${unknown_steps}. Valid steps: ${DEFAULT_METHODS.keySet()}"
        )
      }

      def methods = DEFAULT_METHODS.collectEntries { step, default_method ->
        def entry = user_cfg[step] ?: [:]
        // allow the short form `step: method_name`
        if (entry instanceof String) entry = [method: entry]
        def method = entry.method ?: default_method
        // Fail on unknown methods: runEach would otherwise filter everything out and the
        // pipeline would end with an empty channel instead of an error
        if (!(method in available[step])) {
          throw new IllegalArgumentException(
            "[$id] Unknown method '$method' for step '$step'. Valid methods: ${available[step]}"
          )
        }
        [(step): [method: method, args: entry.args ?: [:]]]
      }

      [id, state + [methods: methods, steps: []]]
    }

  /****************************************
   *   SEGMENTATION -> ASSIGNMENT -> QC   *
   ****************************************/
  qc_filter_ch = init_ch
    | runStep(segm_methods, "segmentation", "output_segmentation") { state ->
      [input: state.input_sp]
    }
    | runStep(ass_methods, "transcript_assignment", "output_assignment") { state ->
      [
        input_ist: state.input_sp,
        input_scrnaseq: state.input_sc,
        input_segmentation: state.output_segmentation
      ]
    }
    | runStep(count_aggr_methods, "count_aggregation", "output_count_aggregation") { state ->
      [input: state.output_assignment]
    }
    | runStep(qc_filter_methods, "qc_filtering", "output_qc_filter") { state ->
      [input: state.output_count_aggregation]
    }

  /****************************************
   *    VOLUME CALCULATION + NORMALIZATION *
   ****************************************/
  // The volume step is a dependency of normalize_by_volume, not an independent choice:
  // it only runs when that normalization is selected.
  norm_branch_ch = qc_filter_ch
    | branch { tup ->
      by_volume: tup[1].methods.normalization.method in vol_norm_methods.collect { it.config.name }
      direct: true
    }

  vol_norm_ch = norm_branch_ch.by_volume
    | runStep(cell_vol_methods, "volume_calculation", "output_cell_volume") { state ->
      [input: state.output_assignment]
    }
    | runStep(vol_norm_methods, "normalization", "output_normalization") { state ->
      [
        input_spatial_aggregated_counts: state.output_count_aggregation,
        input_cell_volumes: state.output_cell_volume
      ]
    }

  direct_norm_ch = norm_branch_ch.direct
    | runStep(direct_norm_methods, "normalization", "output_normalization") { state ->
      [input_spatial_aggregated_counts: state.output_count_aggregation]
    }

  /****************************************
   *  ANNOTATION -> CORRECTION -> AGGREGATE *
   ****************************************/
  output_ch = vol_norm_ch.mix(direct_norm_ch)
    | runStep(cta_methods, "celltype_annotation", "output_cta") { state ->
      [
        input_spatial_normalized_counts: state.output_normalization,
        input_transcript_assignments: state.output_assignment,
        input_scrnaseq_reference: state.input_sc
      ]
    }
    | runStep(expr_corr_methods, "expression_correction", "output_correction") { state ->
      [
        input_spatial_with_cell_types: state.output_cta,
        input_scrnaseq_reference: state.input_sc
      ]
    }
    // overwrites output_correction, so the aggregation below sees the final counts
    | runStep(gene_eff_methods, "gene_efficiency_correction", "output_correction") { state ->
      [
        input: state.output_correction,
        input_scrnaseq_reference: state.input_sc
      ]
    }
    | aggregate_spatial_data.run(
      fromState: [
        input_raw_sp: "input_sp",
        input_transcript_assignments: "output_assignment",
        input_qc_col: "output_qc_filter",
        input_spatial_corrected_counts: "output_correction"
      ],
      toState: [output_agg_spatial_data: "output"]
    )
    | setState([
      output: "output_agg_spatial_data",
      output_counts: "output_correction"
    ])

  emit:
  output_ch
}

/**
 * Run the one method selected for a step.
 *
 * All candidate components are passed to runEach and filtered down to the one named in
 * state.methods[step_key].method; that step's args from the user config are added to the
 * component's inputs. The ids are left unchanged: there is a single path per dataset.
 *
 * @param components Candidate components for this step
 * @param step_key Step name, as used in the methods config
 * @param output_key State key the component's output is stored under
 * @param input_fn Closure state -> map of component inputs
 * @return Workflow that takes and emits [id, state] tuples
 */
def runStep(components, step_key, output_key, input_fn) {
  return runEach(
    components: components,
    filter: { id, state, comp ->
      comp.config.name == state.methods[step_key].method
    },
    fromState: { id, state, comp ->
      input_fn(state) + state.methods[step_key].args
    },
    toState: { id, out_dict, state, comp ->
      state + [
        steps: state.steps + [[
          type: step_key,
          component_id: comp.config.name,
          args: state.methods[step_key].args
        ]],
        (output_key): out_dict.output
      ]
    }
  )
}
