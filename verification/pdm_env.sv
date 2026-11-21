/* Eric Phong, rfp479, CME435, 11344905, Lab5 */

// Environment: 1 upstream agent, 4 downstream agents, and (Lab 5) the
// predictor, scoreboard and coverage collector.
//
//   upstream_agent.monitor.upstream_txn_ap --+--> predictor --> scoreboard.exp_imp
//                                            +--> coverage.up_imp
//   downstream_agent_i.monitor.downstream_txn_ap --+--> scoreboard.act_imp
//                                                  +--> coverage.dn_imp
`ifndef PDM_ENV_SV
`define PDM_ENV_SV

class pdm_env extends uvm_env;

    // Factory Registration
    `uvm_component_utils(pdm_env)

    // Config & Constructs
    pdm_env_cfg          env_cfg;

    pdm_upstream_agent   upstream_agent;
    pdm_downstream_agent downstream_agent[4];

    // Lab 5: analysis components
    pdm_predictor        predictor;
    pdm_scoreboard       scoreboard;
    pdm_coverage         coverage;

    // Constructor
    function new(string name = "pdm_env", uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // Builder Phase
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Get config info from config_data base
        if(!uvm_config_db#(pdm_env_cfg)::get(this, "", "env_cfg", env_cfg)) begin
            `uvm_fatal(get_type_name(), "pdm_env_cfg not found in config_db")
        end

        // Register upstream agent configuration and instantiate upstream agent
        uvm_config_db#(pdm_upstream_agent_cfg)::set(this, "upstream_agent*", "cfg", env_cfg.upstream_cfg);
        upstream_agent = pdm_upstream_agent::type_id::create("upstream_agent", this);

        // Register downstream agent configurations and instantiate 4 downstream agents
        for(int i = 0; i < 4; i++) begin
            uvm_config_db#(pdm_downstream_agent_cfg)::set(
                this,
                $sformatf("downstream_agent_%0d*", i),
                "cfg",
                env_cfg.downstream_cfg[i]
            );
            downstream_agent[i] = pdm_downstream_agent::type_id::create($sformatf("downstream_agent_%0d", i), this);
        end

        // Lab 5: analysis components
        if (env_cfg.has_scoreboard) begin
            predictor  = pdm_predictor::type_id::create("predictor", this);
            scoreboard = pdm_scoreboard::type_id::create("scoreboard", this);
        end
        if (env_cfg.has_coverage)
            coverage = pdm_coverage::type_id::create("coverage", this);
    endfunction : build_phase

    // Connect Phase (Lab 5): children are all built now, so handles are valid.
    // Rule: producer port .connect( consumer export/imp )
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        if (env_cfg.has_scoreboard) begin
            upstream_agent.monitor.upstream_txn_ap.connect(predictor.analysis_export);
            predictor.ap.connect(scoreboard.exp_imp);
            // All 4 output monitors share one imp; item.port_id selects the queue
            foreach (downstream_agent[i])
                downstream_agent[i].monitor.downstream_txn_ap.connect(scoreboard.act_imp);
        end

        if (env_cfg.has_coverage) begin
            upstream_agent.monitor.upstream_txn_ap.connect(coverage.up_imp);
            foreach (downstream_agent[i])
                downstream_agent[i].monitor.downstream_txn_ap.connect(coverage.dn_imp);
        end
    endfunction : connect_phase

endclass : pdm_env

`endif // PDM_ENV_SV
