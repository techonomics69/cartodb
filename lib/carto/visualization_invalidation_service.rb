module Carto
  class VisualizationInvalidationService
    def initialize(visualization)
      @visualization = visualization
      @invalidate_affected_visualizations = false
    end

    def invalidate
      invalidate_caches
      update_or_destroy_named_map
      invalidate_affected_visualizations if @invalidate_affected_visualizations
    end

    def with_invalidation_of_affected_visualizations
      @invalidate_affected_visualizations = true
      self
    end

    protected

    def invalidate_caches
      invalidate_embeds_from_redis
      invalidate_vizjson_from_redis
      invalidate_vizjson_from_varnish
    end

    private

    def update_or_destroy_named_map
      return if @visualization.remote?
      named_maps_api = Carto::NamedMaps::Api.new(@visualization.for_presentation)
      if @visualization.destroyed?
        named_maps_api.destroy
      elsif @visualization.data_layers.any?
        named_maps_api.show ? named_maps_api.update : named_maps_api.create
      end
    end

    def invalidate_affected_visualizations
      @visualization.user_table.dependent_visualizations.each do |affected_visualization|
        VisualizationInvalidationService.new(affected_visualization).invalidate_caches
      end
    end

    def invalidate_embeds_from_redis
      EmbedRedisCache.new($tables_metadata).invalidate(@visualization.id)
    end

    def invalidate_vizjson_from_redis
      CartoDB::Visualization::RedisVizjsonCache.new.invalidate(@visualization.id)
    end

    def invalidate_vizjson_from_varnish
      CartoDB::Varnish.new.purge(".*#{@visualization.id}:vizjson")
    end
  end
end