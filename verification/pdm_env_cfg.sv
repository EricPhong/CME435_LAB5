/* Eric Phong, rfp479, CME435, 11344905, Lab5 */ 
 
// Configuration for the one upstream and four downstream agents.
class pdm_env_cfg extends uvm_object; // extend objects
    `uvm_object_utils(pdm_env_cfg)//factory

    // agent config handles
    pdm_upstream_agent_cfg   upstream_cfg; 
    pdm_downstream_agent_cfg downstream_cfg[4];

    // Lab 5: analysis component switches
    bit has_scoreboard = 1; // predictor + scoreboard
    bit has_coverage   = 1; // functional coverage collector

    // constructor
    function new(string name = "pdm_env_cfg");
        super.new(name);
        upstream_cfg = pdm_upstream_agent_cfg::type_id::create("upstream_cfg");
        foreach (downstream_cfg[i])
            downstream_cfg[i] = pdm_downstream_agent_cfg::type_id::create(
                $sformatf("downstream_cfg_%0d", i));
    endfunction
endclass
